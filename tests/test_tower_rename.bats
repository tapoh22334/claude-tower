#!/usr/bin/env bats
# `tower rename` (value/001-tower-session-cli, UC1): the CLI contract on
# top of set_session_name — target resolution, exit codes, stdout/stderr
# separation, and that nothing asks a question.

load 'test_helper'

T="$PROJECT_ROOT/tmux-plugin/scripts/tower.sh"
ID="tower_11111111-0000-4000-8000-000000000001"

setup() {
    source_common
    setup_test_env
    save_metadata "$ID" "" "/tmp/x"
}

teardown() {
    teardown_test_env
}

@test "rename: --session names the target; stdout is the id alone, the message is on stderr" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename "payments 移行" --session "$ID"
    [ "$status" -eq 0 ]
    [ "$output" = "$ID" ]
    run bash -c "env -u TMUX -u TMUX_PANE '$T' rename x --session '$ID' 2>&1 >/dev/null"
    [[ "$output" == *"Renamed"* ]]
    load_metadata "$ID"
    [ "$META_SESSION_NAME" = "x" ]
}

@test "rename: accepts the bare uuid as --session" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename x --session "${ID#tower_}"
    [ "$status" -eq 0 ]
    [ "$output" = "$ID" ]
}

@test "rename: keeps created_at, launch_dir and live_id" {
    record_live_id "$ID" "22222222-0000-4000-8000-000000000002"
    local before
    before=$(grep -v '^session_name=' "$TOWER_METADATA_DIR/$ID.meta")
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename x --session "$ID"
    [ "$status" -eq 0 ]
    [ "$(grep -v '^session_name=' "$TOWER_METADATA_DIR/$ID.meta")" = "$before" ]
}

@test "rename: --clear removes the name" {
    set_session_name "$ID" "old"
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename --clear --session "$ID"
    [ "$status" -eq 0 ]
    [ "$output" = "$ID" ]
    ! grep -q '^session_name=' "$TOWER_METADATA_DIR/$ID.meta"
}

@test "rename: outside a Tower pane without --session exits 2 and says so" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename foo
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"--session"* ]]
    ! grep -q '^session_name=' "$TOWER_METADATA_DIR/$ID.meta"
}

@test "rename: inside a Tower pane the calling session is the target" {
    session_tmux new-session -d -s "$ID" "sleep 30"
    local pane sock
    pane=$(session_tmux display-message -p -t "$ID" '#{pane_id}')
    sock=$(session_tmux display-message -p -t "$ID" '#{socket_path}')
    run --separate-stderr env TMUX="$sock,1,0" TMUX_PANE="$pane" "$T" rename "from inside"
    [ "$status" -eq 0 ]
    [ "$output" = "$ID" ]
    load_metadata "$ID"
    [ "$META_SESSION_NAME" = "from inside" ]
}

@test "rename: an empty or blank name exits 2 without touching metadata" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename "" --session "$ID"
    [ "$status" -eq 2 ]
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename "   " --session "$ID"
    [ "$status" -eq 2 ]
    ! grep -q '^session_name=' "$TOWER_METADATA_DIR/$ID.meta"
}

@test "rename: --clear combined with a name exits 2" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename --clear x --session "$ID"
    [ "$status" -eq 2 ]
}

@test "rename: an unregistered session exits 1" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename x --session tower_zzzzzzzz-0000-4000-8000-000000000009
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"not registered"* ]]
}

@test "rename: completes with stdin closed (no confirmation prompt)" {
    run --separate-stderr timeout 10 env -u TMUX -u TMUX_PANE "$T" rename x --session "$ID" </dev/null
    [ "$status" -eq 0 ]
}

@test "rename: unknown option exits 2" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename --bogus x --session "$ID"
    [ "$status" -eq 2 ]
}
