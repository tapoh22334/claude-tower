#!/usr/bin/env bats
# Queue view: ordering (longest wait first), frame layout, key wiring.
# queue-view.sh has a BASH_SOURCE guard, so it can be sourced; sourcing it
# pulls in readonly common.sh, so tests run in a fresh bash.

load 'test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# $1 = snippet run after sourcing queue-view.sh
_run_queue() {
    run bash -c '
        export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'"
        export CLAUDE_PROJECTS_DIR="'"$CLAUDE_PROJECTS_DIR"'"
        export CLAUDE_TOWER_NAV_SOCKET="queue-nav-$$"
        export CLAUDE_TOWER_SESSION_SOCKET="queue-sess-$$"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/queue-view.sh"
        set +e
        tput() { case "$1" in cols) echo 80 ;; lines) echo 24 ;; ed) printf "" ;; *) command tput "$@" 2>/dev/null ;; esac; }
        '"$1"'
    '
}

@test "queue-view.sh: sourcing does not run main (BASH_SOURCE guard)" {
    _run_queue 'echo SOURCED_OK'
    [ "$status" -eq 0 ]
    [[ "$output" == *"SOURCED_OK"* ]]
}

@test "load_queue: orders waiters longest-wait-first and skips non-waiters" {
    _run_queue '
        # a: waited longest (oldest since), b: newest, c: not waiting.
        list_all_sessions() { echo "tower_a:active"; echo "tower_b:active"; echo "tower_c:active"; }
        get_wait_state() { case "$1" in tower_c) echo "" ;; *) echo input ;; esac; }
        wait_since() { case "$1" in tower_a) echo 1000 ;; tower_b) echo 5000 ;; esac; }
        format_relative_time() { echo "x ago"; }
        load_queue
        printf "%s\n" "${QUEUE_IDS[*]}"
    '
    [ "$status" -eq 0 ]
    # a (since 1000, older) before b (since 5000); c excluded entirely.
    [[ "$output" == *"tower_a tower_b"* ]]
    [[ "$output" != *"tower_c"* ]]
}

@test "build_queue_frame: empty queue shows the caught-up message" {
    _run_queue '
        QUEUE_IDS=(); QUEUE_KINDS=(); QUEUE_AGES=()
        build_queue_frame 24 80
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing waiting"* ]]
}

@test "build_queue_frame: a row shows the wait icon and the age" {
    _run_queue '
        _queue_label() { echo "fix the bug"; }
        QUEUE_IDS=("tower_a"); QUEUE_KINDS=("permission"); QUEUE_AGES=("3m")
        build_queue_frame 24 80 | sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚠"* ]]
    [[ "$output" == *"fix the bug"* ]]
    [[ "$output" == *"3m"* ]]
}

@test "build_queue_frame: never exceeds the terminal height" {
    _run_queue '
        _queue_label() { echo "t"; }
        QUEUE_IDS=(); QUEUE_KINDS=(); QUEUE_AGES=()
        for i in $(seq 1 40); do QUEUE_IDS+=("tower_$i"); QUEUE_KINDS+=("input"); QUEUE_AGES+=("1m"); done
        raw=$(build_queue_frame 12 80)
        printf "%s" "$raw" | grep -c ""
    '
    [ "$status" -eq 0 ]
    [ "$output" -le 12 ]
}

@test "build_queue_frame: last line has no trailing newline (endless-scroll class)" {
    _run_queue '
        _queue_label() { echo "t"; }
        QUEUE_IDS=(); QUEUE_KINDS=(); QUEUE_AGES=()
        for i in $(seq 1 40); do QUEUE_IDS+=("tower_$i"); QUEUE_KINDS+=("input"); QUEUE_AGES+=("1m"); done
        raw=$(build_queue_frame 12 80; printf SENTINEL)
        last="${raw##*$'"'"'\n'"'"'}"
        printf "%s" "$last"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"more"*"SENTINEL"* ]]
}

@test "build_queue_frame: overflow collapses into a +N more line" {
    _run_queue '
        _queue_label() { echo "t"; }
        QUEUE_IDS=(); QUEUE_KINDS=(); QUEUE_AGES=()
        for i in $(seq 1 40); do QUEUE_IDS+=("tower_$i"); QUEUE_KINDS+=("input"); QUEUE_AGES+=("1m"); done
        build_queue_frame 12 80 | sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"more"* ]]
}

@test "_wait_icon: each wait kind maps to its glyph" {
    _run_queue '
        printf "%s %s %s %s\n" "$(_wait_icon permission)" "$(_wait_icon question)" "$(_wait_icon input)" "$(_wait_icon error)"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "⚠ ？ ✱ ✗" ]
}

@test "navigator-list.sh: w key is wired to switch_to_queue" {
    run grep -A 2 "^                w)" "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"switch_to_queue"* ]]
}

@test "navigator-list.sh: switch_to_queue launches queue-view.sh on the session server" {
    # Asserted by calling the function with tmux stubbed, not by grepping the
    # source: the three switch_to_* functions share one helper now, so the
    # new-window call no longer sits inside switch_to_queue's own body.
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/navigator-list.sh"
        set +e
        session_tmux() {
            case "$1" in
                list-sessions) echo "tower_stub" ;;
                new-window) printf "new-window %s\n" "$*" ;;
            esac
        }
        nav_tmux() { :; }
        handle_error() { :; }
        handle_info() { :; }
        switch_to_queue
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"new-window"* ]]
    [[ "$output" == *"queue-view.sh"* ]]
    # The window must be pinned to the session the user gets attached to.
    [[ "$output" == *"-t tower_stub"* ]]
}
