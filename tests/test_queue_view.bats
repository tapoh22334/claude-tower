#!/usr/bin/env bats
# Queue view: ordering (most recent wait first), frame layout, key wiring.
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

@test "load_queue: orders waiters most-recent-wait-first and skips non-waiters" {
    _run_queue '
        # a: waited longest (oldest since), b: newest, c: not waiting.
        list_all_session_ids() { echo tower_a; echo tower_b; echo tower_c; }
        get_wait_state() { case "$1" in tower_c) echo "" ;; *) echo input ;; esac; }
        wait_since() { case "$1" in tower_a) echo 1000 ;; tower_b) echo 5000 ;; esac; }
        format_relative_time() { echo "x ago"; }
        load_queue
        printf "%s\n" "${QUEUE_IDS[*]}"
    '
    [ "$status" -eq 0 ]
    # b (since 5000, newer) before a (since 1000); c excluded entirely.
    [[ "$output" == *"tower_b tower_a"* ]]
    [[ "$output" != *"tower_c"* ]]
}

@test "load_queue: does not compute display states it never shows" {
    # list_all_sessions runs get_display_state per session (~0.7s for 24);
    # the queue only needs the ids (#86).
    _run_queue '
        list_all_session_ids() { echo tower_a; }
        list_all_sessions() { echo CALLED >&2; echo "tower_a:active"; }
        list_live_claude_processes() { :; }
        get_wait_state() { echo input; }
        wait_since() { echo 1000; }
        format_relative_time() { echo "x ago"; }
        load_queue
        printf "%s\n" "${QUEUE_IDS[*]}"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"tower_a"* ]]
    [[ "$output" != *"CALLED"* ]]
}

@test "load_queue: the process snapshot does not outlive the load" {
    _run_queue '
        list_all_session_ids() { echo tower_a; }
        list_live_claude_processes() { echo RESCAN >&2; }
        get_wait_state() { echo input; }
        wait_since() { echo 1000; }
        queue_label() { echo t; }
        format_relative_time() { echo "x ago"; }
        load_queue 2>/dev/null
        is_claude_process_alive a 2>&1 || true
    '
    [[ "$output" == *"RESCAN"* ]]
}

@test "render_frame: j/k redraws do not look up each row again" {
    # Each row's label reads its transcript; doing that on every keypress
    # made j/k take ~0.4s with 22 rows (#86).
    _run_queue '
        QUEUE_IDS=(tower_a tower_b tower_c); QUEUE_KINDS=(input input input); QUEUE_AGES=(1m 2m 3m)
        queue_label() { echo L >>"'"$BATS_TEST_TMPDIR"'/label.calls"; echo "t"; }
        render_frame >/dev/null
        handle_key() { SELECTED_INDEX=$(( (SELECTED_INDEX + 1) % 3 )); }
        for i in 1 2 3 4 5; do handle_key j; render_frame >/dev/null; done
        grep -c "" "'"$BATS_TEST_TMPDIR"'/label.calls"
    '
    [ "$status" -eq 0 ]
    [ "${lines[-1]}" -eq 3 ]
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
        queue_label() { echo "fix the bug"; }
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
        queue_label() { echo "t"; }
        QUEUE_IDS=(); QUEUE_KINDS=(); QUEUE_AGES=()
        for i in $(seq 1 40); do QUEUE_IDS+=("tower_$i"); QUEUE_KINDS+=("input"); QUEUE_AGES+=("1m"); done
        raw=$(build_queue_frame 12 80)
        printf "%s" "$raw" | grep -c ""
    '
    [ "$status" -eq 0 ]
    [ "$output" -le 12 ]
}

@test "build_queue_frame: key help is the last line, with no trailing newline (endless-scroll class)" {
    _run_queue '
        queue_label() { echo "t"; }
        QUEUE_IDS=(); QUEUE_KINDS=(); QUEUE_AGES=()
        for i in $(seq 1 40); do QUEUE_IDS+=("tower_$i"); QUEUE_KINDS+=("input"); QUEUE_AGES+=("1m"); done
        raw=$(build_queue_frame 12 80; printf SENTINEL)
        last="${raw##*$'"'"'\n'"'"'}"
        printf "%s" "$last"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"q quit"*"SENTINEL"* ]]
}

@test "build_queue_frame: fills the terminal height so the key help sits on the bottom line" {
    _run_queue '
        queue_label() { echo "t"; }
        QUEUE_IDS=(tower_a); QUEUE_KINDS=(input); QUEUE_AGES=(1m); QUEUE_PROJECTS=(p)
        raw=$(build_queue_frame 12 80)
        echo "nl=$(printf "%s" "$raw" | grep -c "")"
    '
    [ "$status" -eq 0 ]
    # grep -c counts the unterminated last line too: 12 lines on screen.
    [[ "$output" == *"nl=12"* ]]
}

@test "build_queue_frame: rows carry the 1-9 key number, the project and the title" {
    _run_queue '
        QUEUE_IDS=(tower_a tower_b); QUEUE_KINDS=(permission question); QUEUE_AGES=(2m 15m)
        QUEUE_PROJECTS=(claude-tower wiki); QUEUE_LABELS=("fix the bug" "page layout")
        build_queue_frame 24 80 | sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *" 1 ⚠ claude-tower  fix the bug"* ]]
    [[ "$output" == *" 2 ？ wiki          page layout"* ]]
    [[ "$output" == *"2 waiting"* ]]
}

@test "build_queue_frame: the selected row stays reversed past its colored parts" {
    # A full reset (\033[0m) inside the row would end the reverse video at
    # the icon; the row's parts must close with attribute-off codes only.
    _run_queue '
        QUEUE_IDS=(tower_a); QUEUE_KINDS=(permission); QUEUE_AGES=(2m)
        QUEUE_PROJECTS=(p); QUEUE_LABELS=(t); SELECTED_INDEX=0
        _compose_queue_rows
        row="${QUEUE_ROWS[0]}"
        [[ "$row" == *$'"'"'\033[0m'"'"'* ]] && echo HAS_RESET || echo NO_RESET
    '
    [ "$status" -eq 0 ]
    [ "$output" = "NO_RESET" ]
}

@test "_wait_color: each wait kind has its own color" {
    _run_queue '
        for k in permission question input error; do _wait_color "$k" | od -An -c | tr -d " \n"; echo; done | sort -u | wc -l
    '
    [ "$status" -eq 0 ]
    [ "$output" -eq 4 ]
}

@test "build_queue_frame: overflow collapses into a +N more line" {
    _run_queue '
        queue_label() { echo "t"; }
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
        # the last value. What must hold is that every move fires one. The
        # job is disowned, so poll for its line instead of waiting on it.
        _await_redirects() {
            local n
            for n in {1..250}; do
                [[ $(wc -l <"'"$BATS_TEST_TMPDIR"'/redirects" 2>/dev/null) -ge $1 ]] && return 0
                sleep 0.02
            done
        }
        handle_key j; _await_redirects 1
        handle_key G; _await_redirects 2
    '
    [ "$status" -eq 0 ]
    run cat "$BATS_TEST_TMPDIR/redirects"
    [ "${lines[0]}" = "redirect:tower_b" ]
    [ "${lines[1]}" = "redirect:tower_c" ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "queue-view.sh: a move's redirect is not left in the job table" {
    # Same reason as the list loop: see "job table" in test_navigator_cache.bats.
    run bash -c '
        export CLAUDE_TOWER_NAV_STATE_DIR="'"$BATS_TEST_TMPDIR"'/state"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/queue-view.sh"
        set +e
        nav_redirect_view() { sleep 1; }
        QUEUE_IDS=(tower_a); SELECTED_INDEX=0
        _follow_selection
        jobs -p
    '
    [ "$status" -eq 0 ]
    [ -z "$output" ]
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

@test "load_queue: an unknown wait time shows as ?, not an age counted from the epoch" {
    _run_queue '
        collect_queue() { printf "%s\t%s\t%s\t%s\t%s\n" 0 tower_a error p t; }
        load_queue
        echo "age=${QUEUE_AGES[0]}"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "age=?" ]
}

@test "load_queue: the cursor stays on its session when a new wait enters at the top" {
    # Newest waits enter at row 0. Kept by row number, the highlight would
    # move to another session than the view pane shows.
    _run_queue '
        nav_redirect_view() { echo REDIRECT; }
        collect_queue() { printf "%s\t%s\t%s\t%s\t%s\n" 2000 tower_x input p x 1000 tower_y input p y; }
        load_queue; SELECTED_INDEX=0
        collect_queue() { printf "%s\t%s\t%s\t%s\t%s\n" 3000 tower_new input p n 2000 tower_x input p x 1000 tower_y input p y; }
        load_queue
        echo "sel=${QUEUE_IDS[$SELECTED_INDEX]}"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"sel=tower_x"* ]]
    [[ "$output" != *"REDIRECT"* ]]
}

@test "build_queue_frame: rows fit a pane narrower than 50 columns" {
    # The list pane is 30% of the terminal. A row wider than the pane wraps,
    # and a full-height frame that wraps scrolls on every redraw.
    _run_queue '
        TOWER_TERM_COLS=40 TOWER_TERM_LINES=10
        QUEUE_IDS=(tower_a tower_b); QUEUE_KINDS=(permission input); QUEUE_AGES=(2m 15m)
        QUEUE_PROJECTS=(a-rather-long-project wiki); QUEUE_LABELS=("a long title that goes on and on and on" "x")
        _compose_queue_rows
        build_queue_frame 10 40 | sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g" | while IFS= read -r l || [[ -n "$l" ]]; do str_display_width "$l"; done | sort -n | tail -1
    '
    [ "$status" -eq 0 ]
    [ "$output" -le 40 ]
}

@test "_project_col_width: short project names keep their column" {
    _run_queue '
        QUEUE_PROJECTS=(p ab); _project_col_width 60
        QUEUE_PROJECTS=(p); _project_col_width 25
    '
    [ "$status" -eq 0 ]
    [ "${lines[0]}" -eq 4 ]
    [ "${lines[1]}" -eq 0 ]
}
