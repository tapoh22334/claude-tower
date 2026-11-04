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
        # grep -c counts the last line too, though it has no newline.
        echo "lines=$(printf "%s" "$frame" | grep -c "" || true)"
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
    run grep -A 2 "^                t)" "$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"switch_to_tail"* ]]
}

@test "navigator-list.sh: switch_to_tail launches tail-view.sh on the session server" {
    # Asserted by calling the function with tmux stubbed, not by grepping the
    # source: the three switch_to_* functions share one helper now, so the
    # new-window call no longer sits inside switch_to_tail's own body.
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
        switch_to_tail
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"new-window"* ]]
    [[ "$output" == *"tail-view.sh"* ]]
    # The window must be pinned to the session the user gets attached to.
    [[ "$output" == *"-t tower_stub"* ]]
}

# ----------------------------------------------------------------------------
# Which sessions, and what each block shows (#109)
# ----------------------------------------------------------------------------

_run_tail() {
    run bash -c '
        export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'"
        export CLAUDE_PROJECTS_DIR="'"$CLAUDE_PROJECTS_DIR"'"
        export CLAUDE_TOWER_NAV_SOCKET="tail-nav-$$"
        export CLAUDE_TOWER_SESSION_SOCKET="tail-sess-$$"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/tail-view.sh"
        set +e
        '"$1"'
    '
}

@test "collect_queue all: waiters first by most recent wait, then the rest by activity" {
    _run_tail '
        list_all_session_ids() { printf "%s\n" tower_old tower_new tower_idle_old tower_idle_new; }
        list_live_claude_processes() { :; }
        get_wait_state() { case "$1" in tower_old | tower_new) echo input ;; *) echo "" ;; esac; }
        wait_since() { case "$1" in tower_old) echo 1000 ;; tower_new) echo 2000 ;; tower_idle_old) echo 1500 ;; tower_idle_new) echo 9000 ;; esac; }
        queue_project() { echo p; }
        queue_label() { echo t; }
        collect_queue all | cut -f2,3
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = $'tower_new\tinput' ]
    [ "${lines[1]}" = $'tower_old\tinput' ]
    [ "${lines[2]}" = $'tower_idle_new\t-' ]
    [ "${lines[3]}" = $'tower_idle_old\t-' ]
}

@test "collect_queue: without all, sessions that are not waiting are left out" {
    _run_tail '
        list_all_session_ids() { printf "%s\n" tower_w tower_idle; }
        list_live_claude_processes() { :; }
        get_wait_state() { [[ "$1" == tower_w ]] && echo input || echo ""; }
        wait_since() { echo 1000; }
        queue_project() { echo p; }
        queue_label() { echo t; }
        collect_queue | cut -f2
    '
    [ "$status" -eq 0 ]
    [ "$output" = "tower_w" ]
}

@test "load_sessions: blocks follow the queue order" {
    _run_tail '
        collect_queue() { printf "%s\t%s\t%s\t%s\t%s\n" 2000 tower_b input proj "title b" 1000 tower_a permission proj "title a" 3000 tower_c - proj "title c"; }
        _load_visible_tails() { :; }
        load_sessions
        echo "${SESSION_IDS[*]}"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "tower_b tower_a tower_c" ]
}

@test "build_tail_frame: a block shows the end of the conversation, not the pane" {
    _run_tail '
        SESSION_IDS=(tower_a); SESSION_LABELS=("a"); SESSION_STATES=("$STATE_ACTIVE")
        SESSION_TAILS=($'"'"'old line\n❯ the question\nthe answer'"'"')
        capture_tail_lines() { echo "PANE_STATUS_LINE"; }
        build_tail_frame 6 80
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"❯ the question"* ]]
    [[ "$output" == *"the answer"* ]]
    [[ "$output" != *"PANE_STATUS_LINE"* ]]
    # 6 lines: title + header + 4 output lines; all 3 tail lines fit.
    [[ "$output" == *"old line"* ]]
}

@test "build_tail_frame: only the last lines of a long conversation are shown" {
    _run_tail '
        SESSION_IDS=(tower_a); SESSION_LABELS=("a"); SESSION_STATES=("$STATE_ACTIVE")
        SESSION_TAILS=("$(printf "line%s\n" 1 2 3 4 5 6 7 8 9)")
        build_tail_frame 5 80
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"line9"* ]]
    [[ "$output" == *"line7"* ]]
    [[ "$output" != *"line6"* ]]
}

# A transcript with a prompt, a tool round trip, and a reply.
_write_transcript() {
    local f="$1"
    {
        echo '{"type":"user","message":{"role":"user","content":"first prompt"}}'
        echo '{"type":"assistant","message":{"content":[{"type":"text","text":"first reply"}]}}'
        echo '{"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}'
        echo '{"type":"user","isMeta":true,"message":{"role":"user","content":"meta noise"}}'
        echo '{"type":"user","message":{"role":"user","content":"second prompt"}}'
        echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}'
        echo '{"type":"user","message":{"content":[{"type":"tool_result","content":"TOOL OUTPUT"}]}}'
        echo '{"type":"assistant","message":{"content":[{"type":"text","text":"line one\nline two with a \\n backslash"}]}}'
        echo '{"type":"system","subtype":"turn_duration"}'
    } >"$f"
}

@test "transcript_tail: prompts and replies, without tool traffic or markup" {
    command -v jq >/dev/null || skip "jq not installed"
    _write_transcript "$BATS_TEST_TMPDIR/t.jsonl"
    _run_tail 'transcript_tail "'"$BATS_TEST_TMPDIR"'/t.jsonl" 50 80'
    [ "$status" -eq 0 ]
    [[ "$output" == *"❯ first prompt"* ]]
    [[ "$output" == *"first reply"* ]]
    [[ "$output" == *"❯ second prompt"* ]]
    [[ "$output" == *"line one"* ]]
    [[ "$output" == *'line two with a \n backslash'* ]]
    [[ "$output" != *"TOOL OUTPUT"* ]]
    [[ "$output" != *"command-name"* ]]
    [[ "$output" != *"meta noise"* ]]
    [[ "$output" != *"turn_duration"* ]]
}

@test "transcript_tail: prints only the last N lines" {
    command -v jq >/dev/null || skip "jq not installed"
    _write_transcript "$BATS_TEST_TMPDIR/t.jsonl"
    _run_tail 'transcript_tail "'"$BATS_TEST_TMPDIR"'/t.jsonl" 2 80'
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [ "${lines[0]}" = "line one" ]
}

@test "transcript_tail: wraps long lines to the width, counting wide characters as two cells" {
    command -v jq >/dev/null || skip "jq not installed"
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"あいうえおかきくけこ"}]}}' >"$BATS_TEST_TMPDIR/w.jsonl"
    _run_tail 'transcript_tail "'"$BATS_TEST_TMPDIR"'/w.jsonl" 10 10'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "あいうえお" ]
    [ "${lines[1]}" = "かきくけこ" ]
}

@test "transcript_tail: a slice that starts mid-line is still read" {
    command -v jq >/dev/null || skip "jq not installed"
    _write_transcript "$BATS_TEST_TMPDIR/t.jsonl"
    _run_tail 'TOWER_TAIL_BYTES=200; transcript_tail "'"$BATS_TEST_TMPDIR"'/t.jsonl" 50 80'
    [ "$status" -eq 0 ]
    [[ "$output" == *"line one"* ]]
}

@test "transcript_tail: no transcript means no tail, so the block falls back to the pane" {
    _run_tail 'transcript_tail "'"$BATS_TEST_TMPDIR"'/missing.jsonl" 5 80; echo "rc=$?"'
    [[ "$output" == *"rc=1"* ]]
}

@test "build_tail_frame: a block not loaded yet stays blank instead of showing the pane" {
    # The terminal grew after the last load: the new block has no state and
    # no tail. The pane's bottom (input box, status line) is what this view
    # replaced, so it must not reappear there.
    _run_tail '
        SESSION_IDS=(tower_a); SESSION_LABELS=("a"); SESSION_STATES=(""); SESSION_TAILS=()
        capture_tail_lines() { echo "PANE_STATUS_LINE"; }
        build_tail_frame 6 80
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"PANE_STATUS_LINE"* ]]
}

@test "transcript_tail: symbols that terminals draw wide (✅ ⭐) count as two cells" {
    command -v jq >/dev/null || skip "jq not installed"
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"✅ done ✅ done ✅ done ✅ done"}]}}' >"$BATS_TEST_TMPDIR/e.jsonl"
    _run_tail 'transcript_tail "'"$BATS_TEST_TMPDIR"'/e.jsonl" 10 20 | while IFS= read -r l; do str_display_width "$l"; done | sort -n | tail -1'
    [ "$status" -eq 0 ]
    [ "$output" -le 20 ]
}

# ----------------------------------------------------------------------------
# Refresh in the background (#110)
# ----------------------------------------------------------------------------

@test "tail view: a key pressed during a refresh moves the cursor before the refresh ends" {
    _run_tail '
        collect_queue() { printf "%s\t%s\t%s\t%s\t%s\n" 2000 tower_x input p x 1000 tower_y input p y; }
        _load_visible_tails() { :; }
        load_sessions; SELECTED_INDEX=0; SELECTED_ID=tower_x
        collect_queue() { sleep 2; printf "%s\t%s\t%s\t%s\t%s\n" 2000 tower_x input p x 1000 tower_y input p y; }
        tail_reload_tick
        handle_key j
        echo "sel=$SELECTED_ID"
        bg_load_discard
    '
    [ "$output" = "sel=tower_y" ]
}

@test "tail view: a finished refresh brings the new order and each block its tail" {
    _run_tail '
        collect_queue() { printf "%s\t%s\t%s\t%s\t%s\n" 1000 tower_a input p a; }
        _load_visible_tails() { :; }
        load_sessions; SELECTED_ID=tower_a
        collect_queue() { printf "%s\t%s\t%s\t%s\t%s\n" 2000 tower_b input p b 1000 tower_a input p a; }
        _load_visible_tails() { echo "tail of b" >"$1/tail.0"; echo "$STATE_ACTIVE" >"$1/state.0"; }
        tail_reload_tick
        for _ in $(seq 50); do tail_reload_tick && break; sleep 0.05; done
        echo "ids=${SESSION_IDS[*]} sel=$SELECTED_ID tail0=${SESSION_TAILS[0]-unset} tail1=${SESSION_TAILS[1]-unset}"
    '
    [ "$output" = "ids=tower_b tower_a sel=tower_a tail0=tail of b tail1=unset" ]
}
