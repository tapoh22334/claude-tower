#!/usr/bin/env bats
# `tower open` (value/001-tower-session-cli, UC2): a new session in a
# directory, the initial prompt handed over through a file, the Navigator
# selection moved, the caller's session untouched.

load 'test_helper'

T="$PROJECT_ROOT/tmux-plugin/scripts/tower.sh"

setup() {
    source_common
    setup_test_env
    PROJ="$BATS_TEST_TMPDIR/foo"
    mkdir -p "$PROJ"
}

teardown() {
    teardown_test_env
}

_sessions() { session_tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -c '^tower_' || true; }

@test "open: starts a session in the directory and prints only its id" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$PROJ"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^tower_[0-9a-f-]{36}$ ]]
    local id="$output"
    session_tmux has-session -t "$id"
    [ "$(session_tmux display-message -p -t "$id" '#{pane_current_path}')" = "$(cd "$PROJ" && pwd -P)" ]
    load_metadata "$id"
    [ "$META_LAUNCH_DIR" = "$(cd "$PROJ" && pwd -P)" ]
    [ ! -e "$TOWER_METADATA_DIR/$id.prompt" ]
}

@test "open: --prompt is saved verbatim and the program is told to read it" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$PROJ" --prompt 'line with "quotes" and $dollar'
    [ "$status" -eq 0 ]
    local id="$output"
    [ "$(cat "$TOWER_METADATA_DIR/$id.prompt")" = 'line with "quotes" and $dollar' ]
    sleep 0.5
    local screen
    screen=$(session_tmux capture-pane -p -J -S -50 -t "$id")
    [[ "$screen" == *"--session-id ${id#tower_}"* ]]
    [[ "$screen" == *"$id.prompt"* ]]
}

@test "open: --prompt-file - reads the prompt from stdin, newlines intact" {
    run --separate-stderr bash -c "printf 'a\nb\n' | env -u TMUX -u TMUX_PANE '$T' open '$PROJ' --prompt-file -"
    [ "$status" -eq 0 ]
    local id="$output"
    [ "$(cat "$TOWER_METADATA_DIR/$id.prompt")" = $'a\nb' ]
}

@test "open: --prompt-file <path> reads that file" {
    printf 'from file\n' >"$BATS_TEST_TMPDIR/p.txt"
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$PROJ" --prompt-file "$BATS_TEST_TMPDIR/p.txt"
    [ "$status" -eq 0 ]
    [ "$(cat "$TOWER_METADATA_DIR/$output.prompt")" = "from file" ]
}

@test "open: moves the Navigator selection to the new session" {
    echo "tower_old" >"$TOWER_NAV_SELECTED_FILE"
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$PROJ"
    [ "$status" -eq 0 ]
    [ "$(cat "$TOWER_NAV_SELECTED_FILE")" = "$output" ]
}

@test "open: succeeds when no Navigator server is running" {
    nav_tmux kill-server 2>/dev/null || true
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$PROJ"
    [ "$status" -eq 0 ]
}

@test "open: leaves the calling session alone" {
    local h="tower_11111111-0000-4000-8000-000000000001"
    session_tmux new-session -d -s "$h" -c /tmp "sleep 30"
    save_metadata "$h" "" "/tmp"
    local before pane sock
    before=$(cat "$TOWER_METADATA_DIR/$h.meta")
    pane=$(session_tmux display-message -p -t "$h" '#{pane_id}')
    sock=$(session_tmux display-message -p -t "$h" '#{socket_path}')
    run --separate-stderr env TMUX="$sock,1,0" TMUX_PANE="$pane" "$T" open "$PROJ"
    [ "$status" -eq 0 ]
    session_tmux has-session -t "$h"
    [ "$(cat "$TOWER_METADATA_DIR/$h.meta")" = "$before" ]
    [ "$(_sessions)" -eq 2 ]
}

@test "open: a missing directory exits 1 and creates no session" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$BATS_TEST_TMPDIR/typo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"typo"* ]]
    [ "$(_sessions)" -eq 0 ]
}

@test "open: an unreadable prompt file exits 1 and creates no session" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$PROJ" --prompt-file "$BATS_TEST_TMPDIR/nonexistent"
    [ "$status" -eq 1 ]
    [ "$(_sessions)" -eq 0 ]
    [ -z "$(ls "$TOWER_METADATA_DIR" 2>/dev/null | grep prompt)" ]
}

@test "open: --prompt and --prompt-file together exit 2" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$PROJ" --prompt a --prompt-file -
    [ "$status" -eq 2 ]
}

@test "open: no directory exits 2" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open
    [ "$status" -eq 2 ]
}

@test "open: completes with stdin closed" {
    run --separate-stderr timeout 20 env -u TMUX -u TMUX_PANE "$T" open "$PROJ" </dev/null
    [ "$status" -eq 0 ]
}
