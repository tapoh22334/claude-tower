#!/usr/bin/env bats
# A Tower row is keyed by the id the session was launched with. Claude can
# switch session inside the pane (/clear starts a new id), after which the
# row kept showing the old transcript's title and state, and the very same
# process was counted as an unmanaged ⚡ claude in the group header (#43).
# The pane's tty is the link: the claude whose tty is the pane's tty is the
# session the row is really showing. The map is built once per list build
# and persisted to the metadata, so the row keeps following that session
# after the pane is gone.

load 'test_helper'

setup() {
    export CLAUDE_LIVE_SESSIONS_DIR="$BATS_TEST_TMPDIR/live"
    source_common
    setup_test_env
    mkdir -p "$CLAUDE_LIVE_SESSIONS_DIR"
    # pid 501 runs live-1 on pts/7 (the pane of tower_reg-0000); pid 502
    # runs stray-2 on pts/9, a plain terminal.
    printf '{"pid":501,"sessionId":"11111111-1111-4111-8111-111111111111","cwd":"/p/one","kind":"interactive"}\n' >"$CLAUDE_LIVE_SESSIONS_DIR/501.json"
    printf '{"pid":502,"sessionId":"22222222-2222-4222-8222-222222222222","cwd":"/p/one","kind":"interactive"}\n' >"$CLAUDE_LIVE_SESSIONS_DIR/502.json"
    list_live_claude_processes() {
        printf '11111111-1111-4111-8111-111111111111\t501\t/p/one\n22222222-2222-4222-8222-222222222222\t502\t/p/one\n'
    }
    ps() {
        echo "ps $*" >>"$BATS_TEST_TMPDIR/ps.calls"
        case "$*" in
            *"-p 501,502"*) printf ' 501 pts/7\n 502 pts/9\n' ;;
            *501*) echo "pts/7" ;;
            *502*) echo "pts/9" ;;
            *) echo "?" ;;
        esac
    }
    session_tmux() {
        case "$1" in
            list-panes) printf 'tower_reg-0000\t/dev/pts/7\n' ;;
            has-session) return 0 ;;
            *) return 1 ;;
        esac
    }
    save_metadata tower_reg-0000 "" /p/one
}

teardown() {
    teardown_test_env
}

LIVE1="11111111-1111-4111-8111-111111111111"

@test "live id: the claude on the pane's tty names the session the row really shows" {
    build_live_id_map
    run live_claude_id tower_reg-0000
    [ "$output" = "$LIVE1" ]
}

@test "live id: the map is built once and read from subshells — one ps per build, not per lookup" {
    build_live_id_map
    a=$(live_claude_id tower_reg-0000)
    b=$(live_claude_id tower_reg-0000)
    c=$(live_claude_id tower_reg-0000)
    [ "$a" = "$LIVE1" ] && [ "$b" = "$LIVE1" ] && [ "$c" = "$LIVE1" ]
    [ "$(grep -c 'ps -o pid=,tty=' "$BATS_TEST_TMPDIR/ps.calls")" -eq 1 ]
}

@test "live id: with no claude on the pane's tty, the registered id stands" {
    session_tmux() { case "$1" in list-panes) printf 'tower_reg-0000\t/dev/pts/42\n' ;; *) return 0 ;; esac; }
    build_live_id_map
    run live_claude_id tower_reg-0000
    [ "$output" = "reg-0000" ]
}

@test "live id: the switch is written to the metadata so it survives the pane" {
    build_live_id_map
    load_metadata tower_reg-0000
    [ "$META_LIVE_ID" = "$LIVE1" ]
    # Pane gone, map empty: the recorded id still drives the row.
    LIVE_ID_MAP=""
    run live_claude_id tower_reg-0000
    [ "$output" = "$LIVE1" ]
}

@test "live id: recording keeps created_at (a re-save would make the row look 'starting' again)" {
    local before
    before=$(grep '^created_at=' "$CLAUDE_TOWER_METADATA_DIR/tower_reg-0000.meta")
    build_live_id_map
    [ "$(grep '^created_at=' "$CLAUDE_TOWER_METADATA_DIR/tower_reg-0000.meta")" = "$before" ]
}

@test "unmanaged count: a claude running inside a Tower pane is not a stray" {
    build_live_id_map
    has_metadata() { return 1; }
    run count_unregistered_processes_in_dir /p/one
    # stray-2 on pts/9 counts; live-1 on the Tower pane pts/7 does not.
    [ "$output" = "1" ]
}

@test "display state: the transcript looked up is the live session's, not the launch id's" {
    build_live_id_map
    _session_is_fresh() { return 1; }
    find_session_jsonl() { echo "$1" >>"$BATS_TEST_TMPDIR/lookups"; return 1; }
    run get_display_state tower_reg-0000
    run cat "$BATS_TEST_TMPDIR/lookups"
    [[ "$output" == *"$LIVE1"* ]]
    [[ "$output" != *"reg-0000"* ]]
}

@test "unread: the seen mark compares against the live session's transcript" {
    build_live_id_map
    find_session_jsonl() { echo "$1" >>"$BATS_TEST_TMPDIR/lookups"; return 1; }
    mark_session_seen tower_reg-0000 || true
    run cat "$BATS_TEST_TMPDIR/lookups"
    [[ "$output" == *"$LIVE1"* ]]
    [[ "$output" != *"reg-0000"* ]]
}

@test "unread: after /clear, new output is checked on the transcript the mark was taken from" {
    # The mark is taken from the live (post-/clear) transcript. Checking the
    # launch id's transcript instead compared it with one that no longer
    # moves, so the session never read as unread again (#87).
    build_live_id_map
    TOWER_SEEN_DIR="$BATS_TEST_TMPDIR/seen"
    local old new
    old=$(create_mock_jsonl "-p-one" "reg-0000" "/p/one")
    new=$(create_mock_jsonl "-p-one" "$LIVE1" "/p/one")
    touch -d "2020-01-01 00:00:00" "$old"
    touch -d "2020-01-02 00:00:00" "$new"
    mark_session_seen tower_reg-0000
    touch -d "2020-01-03 00:00:00" "$new"
    run is_session_unread tower_reg-0000
    [ "$status" -eq 0 ]
}

@test "resume: r restarts the session the user was last in, not the launch id" {
    build_live_id_map
    session_tmux() { case "$1" in has-session) return 1 ;; new-session) return 0 ;; *) echo "tmux $*" ;; esac; }
    _wait_for_shell_ready() { :; }
    _resolve_tower_program() { echo /usr/bin/claude; }
    handle_success() { :; }
    run start_claude_session tower_reg-0000 "$BATS_TEST_TMPDIR" resume
    [[ "$output" == *"--resume $LIVE1"* ]]
}

@test "live id: is_claude_process_alive reads the build's process table, not a rescan" {
    # A rescan walks ~/.claude/sessions with a ps per entry (~0.5s here);
    # the queue and the list ask once per paneless row (#86).
    build_live_id_map
    list_live_claude_processes() { echo x >>"$BATS_TEST_TMPDIR/rescan.calls"; }
    is_claude_process_alive "$LIVE1"
    ! is_claude_process_alive "33333333-3333-4333-8333-333333333333"
    [ ! -e "$BATS_TEST_TMPDIR/rescan.calls" ]
}

@test "live id: the process table is kept even when no pane exists" {
    session_tmux() { case "$1" in list-panes) return 0 ;; *) return 1 ;; esac; }
    build_live_id_map
    list_live_claude_processes() { echo x >>"$BATS_TEST_TMPDIR/rescan.calls"; }
    is_claude_process_alive "$LIVE1"
    [ ! -e "$BATS_TEST_TMPDIR/rescan.calls" ]
}
