#!/usr/bin/env bats
# Library pieces behind `tower rename` / `tower open` / `tower project new`
# (value/001-tower-session-cli): the atomic session_name write, resolving
# "the session I am in", and handing an initial prompt to the program.

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# --- set_session_name -------------------------------------------------------

@test "set_session_name: writes session_name and keeps every other key byte for byte" {
    local id="tower_11111111-0000-4000-8000-000000000001"
    printf 'launch_dir=/tmp/x\ncreated_at=2026-01-01T00:00:00+09:00\nlive_id=22222222-0000-4000-8000-000000000002\n' \
        >"$TOWER_METADATA_DIR/$id.meta"
    set_session_name "$id" "payments 移行"
    load_metadata "$id"
    [ "$META_SESSION_NAME" = "payments 移行" ]
    [ "$META_CREATED_AT" = "2026-01-01T00:00:00+09:00" ]
    [ "$META_LAUNCH_DIR" = "/tmp/x" ]
    [ "$META_LIVE_ID" = "22222222-0000-4000-8000-000000000002" ]
    # exactly one session_name line, no temp file left behind
    [ "$(grep -c '^session_name=' "$TOWER_METADATA_DIR/$id.meta")" -eq 1 ]
    [ -z "$(ls "$TOWER_METADATA_DIR" | grep -v '\.meta$')" ]
}

@test "set_session_name: replaces an existing name instead of adding a second line" {
    local id="tower_11111111-0000-4000-8000-000000000001"
    save_metadata "$id" "old" "/tmp/x"
    set_session_name "$id" "new"
    [ "$(grep -c '^session_name=' "$TOWER_METADATA_DIR/$id.meta")" -eq 1 ]
    load_metadata "$id"
    [ "$META_SESSION_NAME" = "new" ]
}

@test "set_session_name: an empty name removes the key (--clear)" {
    local id="tower_11111111-0000-4000-8000-000000000001"
    save_metadata "$id" "old" "/tmp/x"
    set_session_name "$id" ""
    ! grep -q '^session_name=' "$TOWER_METADATA_DIR/$id.meta"
    load_metadata "$id"
    [ "$META_LAUNCH_DIR" = "/tmp/x" ]
}

@test "set_session_name: fails without touching anything when the session is not registered" {
    run set_session_name "tower_zzzzzzzz-0000-4000-8000-000000000009" "x"
    [ "$status" -ne 0 ]
    [ ! -e "$TOWER_METADATA_DIR/tower_zzzzzzzz-0000-4000-8000-000000000009.meta" ]
}

@test "set_session_name: a name containing = and newlines is stored on one line and read back" {
    local id="tower_11111111-0000-4000-8000-000000000001"
    save_metadata "$id" "" "/tmp/x"
    set_session_name "$id" $'a=b\nc'
    load_metadata "$id"
    [ "$META_SESSION_NAME" = "a=b c" ]
}

# --- current_tower_session --------------------------------------------------

@test "current_tower_session: fails outside tmux" {
    run env -u TMUX -u TMUX_PANE bash -c "source '$PROJECT_ROOT/tmux-plugin/lib/common.sh' 2>/dev/null; current_tower_session"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "current_tower_session: fails inside a tmux pane that is not on the Tower session server" {
    run env TMUX="/tmp/tmux-1000/default,1,0" TMUX_PANE="%3" bash -c "source '$PROJECT_ROOT/tmux-plugin/lib/common.sh' 2>/dev/null; current_tower_session"
    [ "$status" -ne 0 ]
}

@test "current_tower_session: resolves the tower_ session owning the calling pane" {
    local id="tower_11111111-0000-4000-8000-000000000001"
    session_tmux new-session -d -s "$id" "sleep 30"
    local pane sock
    pane=$(session_tmux display-message -p -t "$id" '#{pane_id}')
    sock=$(session_tmux display-message -p -t "$id" '#{socket_path}')
    run env TMUX="$sock,1,0" TMUX_PANE="$pane" bash -c "source '$PROJECT_ROOT/tmux-plugin/lib/common.sh' 2>/dev/null; current_tower_session"
    [ "$status" -eq 0 ]
    [ "$output" = "$id" ]
}

# --- start_claude_session with an initial prompt --------------------------

@test "start_claude_session: a 4th argument makes the program read its first prompt from that file" {
    local id="tower_11111111-0000-4000-8000-000000000001"
    local pf="$TOWER_METADATA_DIR/$id.prompt"
    printf 'summary line 1\nline 2 with "quotes" and $dollar\n' >"$pf"
    start_claude_session "$id" /tmp new "$pf" >/dev/null 2>&1
    sleep 0.5
    local screen
    screen=$(session_tmux capture-pane -p -J -t "$id")
    [[ "$screen" == *"--session-id ${id#tower_}"* ]]
    [[ "$screen" == *'$(cat '* ]]
    [[ "$screen" == *"$id.prompt"* ]]
}

@test "start_claude_session: without a 4th argument the command line is unchanged" {
    local id="tower_11111111-0000-4000-8000-000000000001"
    start_claude_session "$id" /tmp new >/dev/null 2>&1
    sleep 0.5
    local screen
    screen=$(session_tmux capture-pane -p -J -t "$id")
    [[ "$screen" == *"--session-id ${id#tower_}"* ]]
    [[ "$screen" != *'$(cat '* ]]
}

# --- delete_metadata also drops the prompt file ----------------------------

@test "delete_metadata: removes the saved prompt file with the metadata" {
    local id="tower_11111111-0000-4000-8000-000000000001"
    save_metadata "$id" "" "/tmp/x"
    echo hi >"$TOWER_METADATA_DIR/$id.prompt"
    delete_metadata "$id"
    [ ! -e "$TOWER_METADATA_DIR/$id.meta" ]
    [ ! -e "$TOWER_METADATA_DIR/$id.prompt" ]
}

# --- generate_uuid lives in common.sh now ------------------------------------

@test "generate_uuid: returns a v4-shaped uuid from common.sh" {
    run generate_uuid
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}
