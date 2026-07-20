#!/usr/bin/env bats
# Unit tests for tail-view.sh (live multi-session output follow).
#
# tail-view.sh has a BASH_SOURCE guard, so it can be sourced without
# running main. Sourcing it also sources common.sh (readonly vars), so
# every test runs in a fresh `bash -c` subprocess instead of the bats
# process — same pattern as the nav-socket tests in test_coverage_gaps_2.

load 'test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# Source the script with N sessions of the given state, run a snippet.
# $1 = session count, $2 = state variable name (e.g. STATE_DORMANT), $3 = snippet
_run_tail_frame() {
    local count="$1" state_var="$2" snippet="$3"
    run bash -c '
        export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/tail-view.sh"
        set +e
        SESSION_IDS=(); SESSION_LABELS=(); SESSION_STATES=()
        for ((i = 0; i < '"$count"'; i++)); do
            SESSION_IDS+=("tower_s$i")
            SESSION_LABELS+=("? s$i")
            SESSION_STATES+=("${'"$state_var"'}")
        done
        '"$snippet"'
    '
}

@test "build_tail_frame: never exceeds the terminal height (30 sessions, 12 lines)" {
    _run_tail_frame 30 STATE_DORMANT '
        frame=$(build_tail_frame 12 80)
        nl_count=$(printf "%s" "$frame" | grep -c "" || true)
        echo "lines=$((nl_count + 1))"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"lines="* ]]
    local lines="${output##*lines=}"
    [ "$lines" -le 12 ]
}

@test "build_tail_frame: hidden sessions surface as a +N more line" {
    _run_tail_frame 30 STATE_DORMANT 'build_tail_frame 12 80'
    [ "$status" -eq 0 ]
    [[ "$output" == *" more"* ]]
}

@test "build_tail_frame: last line has no trailing newline (endless-scroll regression class)" {
    _run_tail_frame 30 STATE_DORMANT '
        raw=$(build_tail_frame 12 80; printf "SENTINEL")
        last_line="${raw##*$'"'"'\n'"'"'}"
        printf "%s" "$last_line"
    '
    [ "$status" -eq 0 ]
    # If the frame ended with \n, SENTINEL would sit alone on the last line.
    [[ "$output" == *"more"*"SENTINEL"* ]]
}

@test "build_tail_frame: dormant session shows placeholder, not captured output" {
    _run_tail_frame 1 STATE_DORMANT '
        capture_tail_lines() { echo "MUST_NOT_APPEAR"; }
        build_tail_frame 24 80
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"dormant"* ]]
    [[ "$output" != *"MUST_NOT_APPEAR"* ]]
}

@test "build_tail_frame: live session block contains captured pane output" {
    _run_tail_frame 1 STATE_ACTIVE '
        capture_tail_lines() { echo "LIVE_PANE_OUTPUT"; }
        build_tail_frame 24 80
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"LIVE_PANE_OUTPUT"* ]]
}

@test "build_tail_frame: no sessions renders an empty-state message" {
    _run_tail_frame 0 STATE_DORMANT 'build_tail_frame 24 80'
    [ "$status" -eq 0 ]
    [[ "$output" == *"No sessions"* ]]
}

@test "tail-view.sh: sourcing does not run main (BASH_SOURCE guard)" {
    run bash -c '
        export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/tail-view.sh"
        echo "SOURCED_OK"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"SOURCED_OK"* ]]
}

@test "navigator-list.sh: t key is wired to switch_to_tail" {
    run grep -A 2 "^                t)" "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"switch_to_tail"* ]]
}

@test "navigator-list.sh: switch_to_tail launches tail-view.sh on the session server" {
    run grep -A 6 "^switch_to_tail()" "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"tail-view.sh"* ]]
    [[ "$output" == *"session_tmux new-window"* ]]
}
