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
3004 ? bash /x/tmux-plugin/scripts/queue-view.sh
3005 pts/9 vim navigator-list.sh
3006 pts/7 bash /x/tmux-plugin/scripts/tile.sh'
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

@test "orphan pids: an unrelated process that merely mentions the script name is not touched" {
    run _orphan_nav_pids "$PROCS" "$LIVE"
    [[ "$output" != *"3005"* ]]
}

@test "orphan pids: with no live ttys known at all, nothing is killed (a dead server is not a licence)" {
    run _orphan_nav_pids "$PROCS" ""
    [ -z "$output" ]
}

@test "sweep: kills exactly the orphans and logs each" {
    ps() { printf '%s\n' "$PROCS"; }
    nav_tmux() { printf '/dev/pts/4\n/dev/pts/5\n'; }
    session_tmux() { printf '/dev/pts/7\n'; }
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
    kill() { echo "kill $*" >>"$BATS_TEST_TMPDIR/kills"; }
    cleanup_orphan_nav_processes
    [ ! -f "$BATS_TEST_TMPDIR/kills" ]
}
