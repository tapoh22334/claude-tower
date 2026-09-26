#!/usr/bin/env bats
# Navigator processes that lost their terminal (#30). q only detaches, the
# pane-exited hook respawns, and a tmux server going away leaves list/view
# loops with no pane behind them; one such orphan burned 40% CPU for eight
# days. Opening the Navigator sweeps them: a process of ours whose tty is not
# a pane on either Tower server is nobody's.

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

PROCS='3001 pts/4 bash /x/tmux-plugin/scripts/navigator-list.sh
3002 pts/5 bash /x/tmux-plugin/scripts/navigator-view.sh
3003 pts/9 bash /x/tmux-plugin/scripts/navigator-list.sh
3004 ? /bin/bash /x/tmux-plugin/scripts/navigator-view.sh
3005 pts/9 vim /x/tmux-plugin/scripts/navigator-list.sh
3006 pts/7 bash /x/tmux-plugin/scripts/tile.sh
3007 pts/9 bash /x/tmux-plugin/scripts/tile.sh'
LIVE='/dev/pts/4
/dev/pts/5
/dev/pts/7'

@test "orphan pids: a Tower script whose tty is no pane on either server is an orphan" {
    run _orphan_nav_pids "$PROCS" "$LIVE"
    [[ "$output" == *"3003"* ]]
}

@test "orphan pids: a Tower script with no tty at all is an orphan" {
    run _orphan_nav_pids "$PROCS" "$LIVE"
    [[ "$output" == *"3004"* ]]
}

@test "orphan pids: scripts on a live pane tty are left alone" {
    run _orphan_nav_pids "$PROCS" "$LIVE"
    [[ "$output" != *"3001"* ]]
    [[ "$output" != *"3002"* ]]
    [[ "$output" != *"3006"* ]]
}

@test "orphan pids: an editor holding the script's full path is not touched" {
    run _orphan_nav_pids "$PROCS" "$LIVE"
    [[ "$output" != *"3005"* ]]
}

@test "orphan pids: tile/tail outside any pane are not swept (tower tile runs in a plain terminal)" {
    run _orphan_nav_pids "$PROCS" "$LIVE"
    [[ "$output" != *"3007"* ]]
}

@test "orphan pids: with no live ttys known at all, nothing is killed (a dead server is not a licence)" {
    run _orphan_nav_pids "$PROCS" ""
    [ -z "$output" ]
}

@test "sweep: kills exactly the orphans and logs each" {
    ps() { printf '%s\n' "$PROCS"; }
    nav_tmux() { printf '/dev/pts/4\n/dev/pts/5\n'; }
    session_tmux() { printf '/dev/pts/7\n'; }
    _proc_is_this_tower() { return 0; }
    kill() { echo "kill $*" >>"$BATS_TEST_TMPDIR/kills"; }
    cleanup_orphan_nav_processes
    run cat "$BATS_TEST_TMPDIR/kills"
    [[ "$output" == *"-TERM 3003"* ]]
    [[ "$output" == *"-TERM 3004"* ]]
    [[ "$output" != *"3001"* ]]
    [[ "$output" != *"3006"* ]]
}

@test "sweep: never kills this process" {
    ps() { printf '%s ? bash /x/tmux-plugin/scripts/navigator-list.sh\n' "$$"; }
    nav_tmux() { echo "/dev/pts/4"; }
    session_tmux() { :; }
    _proc_is_this_tower() { return 0; }
    kill() { echo "kill $*" >>"$BATS_TEST_TMPDIR/kills"; }
    cleanup_orphan_nav_processes
    [ ! -f "$BATS_TEST_TMPDIR/kills" ]
}

@test "sweep: a second Tower's loops (other socket pair) are left alone" {
    ps() { printf '%s\n' "$PROCS"; }
    nav_tmux() { printf '/dev/pts/4\n/dev/pts/5\n'; }
    session_tmux() { printf '/dev/pts/7\n'; }
    _proc_is_this_tower() { return 1; }
    kill() { echo "kill $*" >>"$BATS_TEST_TMPDIR/kills"; }
    cleanup_orphan_nav_processes
    [ ! -f "$BATS_TEST_TMPDIR/kills" ]
}

@test "sweep: if either server cannot be listed, nothing is killed" {
    ps() { printf '%s\n' "$PROCS"; }
    nav_tmux() { return 1; }
    session_tmux() { printf '/dev/pts/7\n'; }
    _proc_is_this_tower() { return 0; }
    kill() { echo "kill $*" >>"$BATS_TEST_TMPDIR/kills"; }
    cleanup_orphan_nav_processes
    [ ! -f "$BATS_TEST_TMPDIR/kills" ]
}

@test "traps: a loop with the Navigator's signal traps actually stops on TERM" {
    # The old trap restored the terminal and returned, and bash resumes the
    # loop after a handler — so TERM never stopped list/view. Run the same
    # traps around a tight read loop (EOF on /dev/null makes it spin), send
    # TERM, and expect it gone with the TERM exit status.
    bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh"
        nav_install_signal_traps ":"
        while :; do read -rsn1 -t 0.2 k || :; done
    ' </dev/null &
    local pid=$!
    sleep 0.3
    kill -TERM "$pid"
    local rc=0
    wait "$pid" || rc=$?
    [ "$rc" -eq 143 ]
}

# The Navigator has died silently four times: the view logged its cleanup,
# the list loop logged nothing, and neither said whether it was killed or the
# server went away under it. The traps must leave a line saying which script
# ended, how (signal or exit status), so the next death is attributable.
_trap_probe() {
    # $1 = what to do after installing the traps (a bash snippet). Sets
    # PROBE_PID. Output goes to /dev/null: returning the pid through $(...)
    # would hold the substitution open on the background job's stdout.
    bash -c '
        export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'"
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh"
        TOWER_SCRIPT_NAME=probe.sh
        nav_install_signal_traps ":" probe.sh
        '"$1"'
    ' </dev/null >/dev/null 2>&1 &
    PROBE_PID=$!
}

@test "traps: TERM leaves a line naming the script and the signal" {
    _trap_probe 'while :; do read -rsn1 -t 0.2 k || :; done'
    sleep 0.3
    kill -TERM "$PROBE_PID"; wait "$PROBE_PID" 2>/dev/null || true
    run grep 'probe.sh' "$TOWER_LOG_FILE"
    [[ "$output" == *"TERM"* ]]
}

@test "traps: HUP (terminal or server gone) is caught, logged and exits 129" {
    _trap_probe 'while :; do read -rsn1 -t 0.2 k || :; done'
    sleep 0.3
    kill -HUP "$PROBE_PID"
    local rc=0
    wait "$PROBE_PID" || rc=$?
    [ "$rc" -eq 129 ]
    run grep 'probe.sh' "$TOWER_LOG_FILE"
    [[ "$output" == *"HUP"* ]]
}

@test "traps: a normal exit logs the exit status" {
    _trap_probe 'exit 0'
    wait "$PROBE_PID" 2>/dev/null || true
    run grep 'probe.sh' "$TOWER_LOG_FILE"
    [[ "$output" == *"exit"* ]]
    [[ "$output" == *"status 0"* ]]
}

@test "traps: a non-zero exit keeps its status and logs it (the log call must not eat it)" {
    _trap_probe 'exit 3'
    local rc=0
    wait "$PROBE_PID" || rc=$?
    [ "$rc" -eq 3 ]
    run grep 'probe.sh' "$TOWER_LOG_FILE"
    [[ "$output" == *"status 3"* ]]
}
