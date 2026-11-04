#!/usr/bin/env bats
# What a waiting session is waiting on (#111), and reloads that run behind
# the key loop instead of in it (#110).

load 'test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

_run_queue() {
    run bash -c '
        export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'"
        export CLAUDE_PROJECTS_DIR="'"$CLAUDE_PROJECTS_DIR"'"
        export CLAUDE_TOWER_NAV_SOCKET="pending-nav-$$"
        export CLAUDE_TOWER_SESSION_SOCKET="pending-sess-$$"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/queue-view.sh"
        set +e
        '"$1"'
    '
}

_jsonl() { printf '%s\n' "$@" >"$BATS_TEST_TMPDIR/p.jsonl"; }

# ----------------------------------------------------------------------------
# pending_request (#111)
# ----------------------------------------------------------------------------

@test "pending_request: a question shows the question asked" {
    command -v jq >/dev/null || skip "jq not installed"
    _jsonl '{"type":"user","message":{"content":"go"}}' \
        '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"AskUserQuestion","input":{"questions":[{"question":"Which layout?","header":"Layout"}]}}]}}'
    _run_queue 'pending_request "'"$BATS_TEST_TMPDIR"'/p.jsonl"'
    [ "$status" -eq 0 ]
    [ "$output" = "Which layout?" ]
}

@test "pending_request: a permission shows the tool and what it runs on" {
    command -v jq >/dev/null || skip "jq not installed"
    _jsonl '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"rm -rf build\nmake","description":"Clean"}}]}}'
    _run_queue 'pending_request "'"$BATS_TEST_TMPDIR"'/p.jsonl"'
    [ "$status" -eq 0 ]
    [ "$output" = "Bash: rm -rf build make" ]
}

@test "pending_request: a file tool shows its path" {
    command -v jq >/dev/null || skip "jq not installed"
    _jsonl '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/src/app.sh","old_string":"a","new_string":"b"}}]}}'
    _run_queue 'pending_request "'"$BATS_TEST_TMPDIR"'/p.jsonl"'
    [ "$output" = "Edit: /src/app.sh" ]
}

@test "pending_request: a tool that already has its result is not pending" {
    command -v jq >/dev/null || skip "jq not installed"
    _jsonl '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}' \
        '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"x"}]}}'
    _run_queue 'pending_request "'"$BATS_TEST_TMPDIR"'/p.jsonl"; echo "rc=$?"'
    [ "$output" = "rc=1" ]
}

@test "pending_request: of parallel calls, the one still without a result" {
    command -v jq >/dev/null || skip "jq not installed"
    _jsonl '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a"}}]}}' \
        '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Write","input":{"file_path":"/b","content":"x"}}]}}' \
        '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"x"}]}}'
    _run_queue 'pending_request "'"$BATS_TEST_TMPDIR"'/p.jsonl"'
    [ "$output" = "Write: /b" ]
}

@test "pending_request: no transcript means nothing to show" {
    _run_queue 'pending_request "'"$BATS_TEST_TMPDIR"'/missing.jsonl"; echo "rc=$?"'
    [ "$output" = "rc=1" ]
}

@test "_queue_entry: a permission row is labelled with the pending request" {
    _run_queue '
        get_wait_state() { echo permission; }
        wait_since() { echo 1000; }
        queue_project() { echo p; }
        queue_label() { echo "the title"; }
        queue_pending() { echo "Bash: make test"; }
        _queue_entry tower_a | cut -f5
    '
    [ "$output" = "Bash: make test" ]
}

@test "_queue_entry: without a readable request, the row keeps the title" {
    _run_queue '
        get_wait_state() { echo question; }
        wait_since() { echo 1000; }
        queue_project() { echo p; }
        queue_label() { echo "the title"; }
        queue_pending() { return 1; }
        _queue_entry tower_a | cut -f5
    '
    [ "$output" = "the title" ]
}

@test "_queue_entry: a session waiting for a prompt keeps the title" {
    # input means the turn is over: nothing is pending, and the title says
    # which conversation it is.
    _run_queue '
        get_wait_state() { echo input; }
        wait_since() { echo 1000; }
        queue_project() { echo p; }
        queue_label() { echo "the title"; }
        queue_pending() { echo "SHOULD NOT BE USED"; }
        _queue_entry tower_a | cut -f5
    '
    [ "$output" = "the title" ]
}

# ----------------------------------------------------------------------------
# Background reload (#110)
# ----------------------------------------------------------------------------

@test "bg_load_start: returns at once while the load is still running" {
    _run_queue '
        slow() { sleep 1; echo done >"$1/out"; }
        start=$(date +%s%N)
        bg_load_start slow
        elapsed=$((($(date +%s%N) - start) / 1000000))
        bg_load_done && echo "done-early" || echo "running"
        echo "ms=$elapsed"
        bg_load_discard
    '
    [ "${lines[0]}" = "running" ]
    ms="${lines[1]#ms=}"
    [ "$ms" -lt 500 ]
}

@test "bg_load_done: reports the finished load and leaves its output to read" {
    _run_queue '
        quick() { echo hello >"$1/out"; }
        bg_load_start quick
        for _ in $(seq 50); do bg_load_done && break; sleep 0.05; done
        cat "$BG_LOAD_DIR/out"
        bg_load_discard
        [[ -z "$BG_LOAD_DIR" ]] && echo cleared
    '
    [ "${lines[0]}" = "hello" ]
    [ "${lines[1]}" = "cleared" ]
}

@test "bg_load_done: a load that fails still finishes instead of hanging the view" {
    _run_queue '
        broken() { return 3; }
        bg_load_start broken
        for _ in $(seq 50); do bg_load_done && { echo finished; break; }; sleep 0.05; done
        bg_load_discard
    '
    [ "$output" = "finished" ]
}

@test "bg_load_start: a second start while one runs does not start another" {
    _run_queue '
        slow() { sleep 1; }
        bg_load_start slow; first=$BG_LOAD_PID
        bg_load_start slow
        [[ "$BG_LOAD_PID" == "$first" ]] && echo same
        bg_load_discard
    '
    [ "$output" = "same" ]
}

@test "queue view: a key pressed during a reload moves the cursor before the reload ends" {
    _run_queue '
        collect_queue() { printf "%s\t%s\t%s\t%s\t%s\n" 2000 tower_x input p x 1000 tower_y input p y; }
        load_queue; SELECTED_INDEX=0
        _follow_selection() { :; }
        collect_queue() { sleep 2; printf "%s\t%s\t%s\t%s\t%s\n" 2000 tower_x input p x 1000 tower_y input p y; }
        queue_reload_tick            # starts the reload in the background
        handle_key j
        echo "sel=${QUEUE_IDS[$SELECTED_INDEX]}"
        bg_load_discard
    '
    [ "$output" = "sel=tower_y" ]
}

@test "queue view: the finished reload is applied with the cursor kept on its session" {
    _run_queue '
        collect_queue() { printf "%s\t%s\t%s\t%s\t%s\n" 2000 tower_x input p x 1000 tower_y input p y; }
        load_queue; SELECTED_INDEX=1
        _follow_selection() { :; }
        collect_queue() { printf "%s\t%s\t%s\t%s\t%s\n" 3000 tower_new input p n 2000 tower_x input p x 1000 tower_y input p y; }
        queue_reload_tick
        for _ in $(seq 50); do queue_reload_tick && break; sleep 0.05; done
        echo "n=${#QUEUE_IDS[@]} sel=${QUEUE_IDS[$SELECTED_INDEX]}"
    '
    [ "$output" = "n=3 sel=tower_y" ]
}

@test "pending_request: a call left without a result in an earlier turn is not what waits now" {
    command -v jq >/dev/null || skip "jq not installed"
    _jsonl '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"old","name":"Bash","input":{"command":"crashed"}}]}}' \
        '{"type":"user","message":{"content":"next prompt"}}' \
        '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"make test"}}]}}'
    _run_queue 'pending_request "'"$BATS_TEST_TMPDIR"'/p.jsonl"'
    [ "$output" = "Bash: make test" ]
}

@test "bg_load_start: the job gets the terminal size measured by the view" {
    # The job has no terminal on any fd, where tput answers 24x80.
    _run_queue '
        unset TOWER_TERM_LINES TOWER_TERM_COLS
        _term_lines() { echo "${TOWER_TERM_LINES:-61}"; }
        _term_cols() { echo "${TOWER_TERM_COLS:-123}"; }
        probe() { echo "$TOWER_TERM_LINES x $TOWER_TERM_COLS" >"$1/out"; }
        bg_load_start probe
        for _ in $(seq 50); do bg_load_done && break; sleep 0.05; done
        cat "$BG_LOAD_DIR/out"
        bg_load_discard
    '
    [ "$output" = "61 x 123" ]
}

@test "bg_load_discard: stops the checks running under the load, not only the load" {
    _run_queue '
        # The name is built at run time: pgrep -f would match this script.
        name="probe-$$-gc"
        job() { { (exec -a "$name" sleep 30) & wait; } | cat >"$1/q"; }
        bg_load_start job
        sleep 0.3
        bg_load_discard
        sleep 0.2
        pgrep -f "^$name" >/dev/null && echo leaked || echo stopped
    '
    [ "$output" = "stopped" ]
}

@test "queue view: applying a finished reload recomputes nothing" {
    # It runs in the key loop: the formatting belongs to the background job.
    _run_queue '
        _follow_selection() { :; }
        collect_queue() { printf "%s\t%s\t%s\t%s\t%s\n" 2000 tower_x input p x; }
        dir=$(mktemp -d); _queue_snapshot "$dir"
        collect_queue() { echo CALLED >&2; }
        format_relative_time() { echo CALLED >&2; }
        _queue_row() { echo CALLED >&2; }
        _content_width() { cat "$dir/width"; }
        _apply_queue_snapshot "$dir"; _compose_queue_rows
        echo "ids=${QUEUE_IDS[*]} rows=${#QUEUE_ROWS[@]}"
    '
    [ "$output" = "ids=tower_x rows=1" ]
}

@test "bg_load_done: a load killed by a shell error (unbound variable) still finishes" {
    _run_queue '
        set -u
        broken() { echo "$NO_SUCH_VARIABLE_HERE"; }
        bg_load_start broken
        for _ in $(seq 50); do bg_load_done && { echo finished; break; }; sleep 0.05; done
        bg_load_discard
    '
    [ "$output" = "finished" ]
}
