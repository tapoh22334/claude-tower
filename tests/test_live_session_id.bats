#!/usr/bin/env bats
# A Tower row is keyed by the id the session was launched with. Claude can
# switch session inside the pane (/clear starts a new id), after which the
# row kept showing the old transcript's title and state, and the very same
# process was counted as an unmanaged ⚡ claude in the group header (#43).
# The pane's tty is the link: the claude whose tty is the pane's tty is the
# session the row is really showing.

load 'test_helper'

setup() {
    source_common
    setup_test_env
    # Live table: pid 501 runs session live-1 on pts/7; pid 502 runs stray-2
    # on pts/9 (a plain terminal). Pane of tower_reg is pts/7.
    list_live_claude_processes() {
        printf 'live-1\t501\t/p/one\nstray-2\t502\t/p/one\n'
    }
    ps() {
        case "$*" in
            *501*) echo "pts/7" ;;
            *502*) echo "pts/9" ;;
            *) echo "?" ;;
        esac
    }
    session_tmux() {
        case "$1" in
            display-message) echo "/dev/pts/7" ;;
            list-panes) echo "/dev/pts/7" ;;
            has-session) return 0 ;;
            *) return 1 ;;
        esac
    }
    reset_live_id_cache
}

teardown() {
    teardown_test_env
}

@test "live_claude_id: the claude on the pane's tty names the session the row really shows" {
    run live_claude_id tower_reg-0000
    [ "$output" = "live-1" ]
}

@test "live_claude_id: with no claude on the pane's tty, the registered id stands" {
    session_tmux() { case "$1" in display-message) echo "/dev/pts/42" ;; *) return 0 ;; esac; }
    run live_claude_id tower_reg-0000
    [ "$output" = "reg-0000" ]
}

@test "live_claude_id: a session with no pane at all keeps its registered id" {
    session_tmux() { return 1; }
    run live_claude_id tower_reg-0000
    [ "$output" = "reg-0000" ]
}

@test "unmanaged count: a claude running inside a Tower pane is not a stray" {
    has_metadata() { return 1; }
    run count_unregistered_processes_in_dir /p/one
    # stray-2 on pts/9 counts; live-1 on the Tower pane pts/7 does not.
    [ "$output" = "1" ]
}

@test "display state: the transcript looked up is the live session's, not the launch id's" {
    _session_is_fresh() { return 1; }
    find_session_jsonl() { echo "$1" >>"$BATS_TEST_TMPDIR/lookups"; return 1; }
    run get_display_state tower_reg-0000
    run cat "$BATS_TEST_TMPDIR/lookups"
    [[ "$output" == *"live-1"* ]]
    [[ "$output" != *"reg-0000"* ]]
}
