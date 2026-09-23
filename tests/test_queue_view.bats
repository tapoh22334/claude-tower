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
    run sed -n '/^                w)$/,/;;/p' "$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"switch_to_queue"* ]]
}

@test "navigator-list.sh: switch_to_queue runs queue-view.sh in this pane and touches no tmux server" {
    # The queue is a mode of the list pane, not a window on the session
    # server (that design nested the Navigator inside itself — #37). Any tmux
    # call here is a regression, so both wrappers abort the test.
    local fake="$BATS_TEST_TMPDIR/fakescripts"
    mkdir -p "$fake"
    printf '#!/usr/bin/env bash\necho ran-in-pane\nexit 0\n' >"$fake/queue-view.sh"
    chmod +x "$fake/queue-view.sh"
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/navigator-list.sh"
        set +e
        SCRIPT_DIR="'"$fake"'"
        session_tmux() { echo "SESSION_TMUX CALLED: $*"; exit 99; }
        nav_tmux() { echo "NAV_TMUX CALLED: $*"; exit 99; }
        switch_to_queue
    '
    [ "$status" -eq 0 ]
    [ "$output" = "ran-in-pane" ]
}

@test "navigator-list.sh: switch_to_queue reports the queue's quit code to the loop" {
    local fake="$BATS_TEST_TMPDIR/fakescripts"
    mkdir -p "$fake"
    printf '#!/usr/bin/env bash\nexit 3\n' >"$fake/queue-view.sh"
    chmod +x "$fake/queue-view.sh"
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/navigator-list.sh"
        set +e
        SCRIPT_DIR="'"$fake"'"
        switch_to_queue
    '
    [ "$status" -eq 3 ]
}

@test "navigator-list.sh: the w handler resyncs the cursor from the selection after the queue" {
    # The queue writes the chosen id to the selection file; the loop must read
    # it back into selected_index, or the highlight stays where it was before
    # w while D/Enter act on the queue's choice (screen vs state).
    run sed -n '/^                w)$/,/;;/p' "$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"_return_from_subflow"* ]]
    [[ "$output" == *'selected_index=$(get_selection_index)'* ]]
    [[ "$output" == *"quit_navigator"* ]]
    # And the view pane must be pointed at that row: the queue's last redirect
    # may have raced its own exit, and the arrays must be fresh first.
    [[ "$output" == *"_load_session_state"* ]]
    [[ "$output" == *"signal_view_update_async"* ]]
}

# ----------------------------------------------------------------------------
# Exits: the queue hands control back by exiting, never by attaching a client.
# A PATH-shadowed tmux records any call and fails, so an attach from inside
# the pane shows up as both a log line and a non-zero status.
# ----------------------------------------------------------------------------
_shadow_tmux() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/usr/bin/env bash\necho "tmux $*" >>"%s/tmux.log"\nexit 1\n' "$BATS_TEST_TMPDIR" >"$BATS_TEST_TMPDIR/bin/tmux"
    chmod +x "$BATS_TEST_TMPDIR/bin/tmux"
}

@test "queue-view.sh: return_to_list_view writes the selection and exits 0 without attaching" {
    _shadow_tmux
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c '
        export CLAUDE_TOWER_NAV_STATE_DIR="'"$BATS_TEST_TMPDIR"'/state"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/queue-view.sh"
        set +e
        ( return_to_list_view tower_picked ); rc=$?
        echo "rc=$rc sel=$(get_nav_selected)"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0 sel=tower_picked"* ]]
    [ ! -f "$BATS_TEST_TMPDIR/tmux.log" ]
}

@test "queue-view.sh: quit_navigator exits with the quit code without attaching" {
    _shadow_tmux
    run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c '
        export CLAUDE_TOWER_NAV_STATE_DIR="'"$BATS_TEST_TMPDIR"'/state"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/queue-view.sh"
        set +e
        quit_navigator
    '
    [ "$status" -eq 3 ]
    [ ! -f "$BATS_TEST_TMPDIR/tmux.log" ]
}

@test "queue-view.sh: j/k redirect the view pane, not just write the file" {
    # Writing the selection is not enough: the view's nested client is parked
    # inside attach-session and moves only when redirected. Every move must
    # call the shared redirect.
    run bash -c '
        export CLAUDE_TOWER_NAV_STATE_DIR="'"$BATS_TEST_TMPDIR"'/state"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/queue-view.sh"
        set +e
        nav_redirect_view() { echo "redirect:$(get_nav_selected)" >>"'"$BATS_TEST_TMPDIR"'/redirects"; }
        QUEUE_IDS=(tower_a tower_b tower_c); QUEUE_KINDS=(input input input); QUEUE_AGES=(1m 2m 3m)
        SELECTED_INDEX=0
        # One move at a time: the redirect runs in the background and reads
        # the selection when it runs, so a burst legitimately collapses to
        # the last value. What must hold is that every move fires one.
        handle_key j; wait
        handle_key G; wait
    '
    [ "$status" -eq 0 ]
    run cat "$BATS_TEST_TMPDIR/redirects"
    [ "${lines[0]}" = "redirect:tower_b" ]
    [ "${lines[1]}" = "redirect:tower_c" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "common.sh: nav_redirect_view switches the view client onto a live selection" {
    run bash -c '
        export CLAUDE_TOWER_NAV_STATE_DIR="'"$BATS_TEST_TMPDIR"'/state"
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh"
        set +e
        set_nav_selected tower_live
        nav_tmux() { echo "/dev/pts/99"; }
        session_tmux() { echo "session_tmux $*"; }
        nav_redirect_view
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"switch-client -c /dev/pts/99 -t tower_live"* ]]
}

@test "common.sh: nav_redirect_view detaches the view client when the selection is not live" {
    run bash -c '
        export CLAUDE_TOWER_NAV_STATE_DIR="'"$BATS_TEST_TMPDIR"'/state"
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh"
        set +e
        set_nav_selected tower_dormant
        nav_tmux() { echo "/dev/pts/99"; }
        session_tmux() { case "$1" in has-session) return 1 ;; *) echo "session_tmux $*" ;; esac; }
        nav_redirect_view
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"detach-client -t /dev/pts/99"* ]]
    [[ "$output" != *"switch-client"* ]]
}

@test "queue-view.sh: j/k publish the row under the cursor so the view pane follows" {
    run bash -c '
        export CLAUDE_TOWER_NAV_STATE_DIR="'"$BATS_TEST_TMPDIR"'/state"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/queue-view.sh"
        set +e
        QUEUE_IDS=(tower_a tower_b tower_c); QUEUE_KINDS=(input input input); QUEUE_AGES=(1m 2m 3m)
        SELECTED_INDEX=0
        handle_key j; echo "after-j=$(get_nav_selected)"
        handle_key G; echo "after-G=$(get_nav_selected)"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"after-j=tower_b"* ]]
    [[ "$output" == *"after-G=tower_c"* ]]
}

@test "queue-view.sh: the cursor starts on the list's current selection when it is queued" {
    run bash -c '
        export CLAUDE_TOWER_NAV_STATE_DIR="'"$BATS_TEST_TMPDIR"'/state"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/queue-view.sh"
        set +e
        QUEUE_IDS=(tower_a tower_b tower_c)
        set_nav_selected tower_c
        SELECTED_INDEX=0
        _seed_selection
        echo "idx=$SELECTED_INDEX"
    '
    [[ "$output" == *"idx=2"* ]]
}
