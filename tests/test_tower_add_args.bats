#!/usr/bin/env bats
# `tower add <path> [-n name]` — the form tower's own --help has advertised
# from the start. session-add.sh parsed only --print-id/--fork-dir/
# --new-in-dir, so a path and a name were silently discarded and the picker
# opened instead; the user got no indication their arguments were ignored.

load 'test_helper'

setup() {
    source_common
    setup_test_env
    ADD="$PROJECT_ROOT/tmux-plugin/scripts/session-add.sh"
    WORK="$BATS_TEST_TMPDIR/work"
    mkdir -p "$WORK"
}

@test "tower add: a missing directory is refused by name" {
    run bash "$ADD" "$BATS_TEST_TMPDIR/no-such-dir"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Directory not found"* ]]
}

@test "tower add: an unknown option is refused rather than ignored" {
    run bash "$ADD" --definitely-not-a-flag
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown option"* ]]
}

@test "tower add: a path argument starts a session there and records the name" {
    local socket="towerarg-$$"
    local tmpdir="$BATS_TEST_TMPDIR/tmux"
    mkdir -p "$tmpdir"
    chmod 700 "$tmpdir"
    run env \
        TMUX_TMPDIR="$tmpdir" \
        CLAUDE_TOWER_SESSION_SOCKET="$socket" \
        CLAUDE_TOWER_NAV_SOCKET="${socket}-nav" \
        CLAUDE_TOWER_METADATA_DIR="$BATS_TEST_TMPDIR/meta" \
        TOWER_PROGRAM="sleep 30" \
        bash "$ADD" "$WORK" -n my-alias --print-id
    TMUX= TMUX_TMPDIR="$tmpdir" tmux -L "$socket" kill-server 2>/dev/null || true

    [ "$status" -eq 0 ]
    # handle_success prints to stdout too, so the id is the last line.
    local id="${lines[${#lines[@]}-1]}"
    [[ "$id" == tower_* ]]

    local meta="$BATS_TEST_TMPDIR/meta/${id}.meta"
    [ -f "$meta" ]
    run grep -q '^session_name=my-alias$' "$meta"
    [ "$status" -eq 0 ]
}

@test "tower add: --name is accepted as a long form of -n" {
    run grep -qE '^\s+-n \| --name\)' "$ADD"
    [ "$status" -eq 0 ]
}

@test "tower add: -n without a name is an error, not a swallowed flag" {
    # `-n --print-id` used to consume --print-id as the name, so the caller
    # got no id and no explanation.
    run bash "$ADD" -n --print-id
    [ "$status" -ne 0 ]
    [[ "$output" == *"needs a name"* ]]
}

@test "tower add: a trailing -n is an error" {
    run bash "$ADD" -n
    [ "$status" -ne 0 ]
    [[ "$output" == *"needs a name"* ]]
}

@test "tower add: two directories are refused rather than last-wins" {
    run bash "$ADD" "$BATS_TEST_TMPDIR/a" "$BATS_TEST_TMPDIR/b"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Only one directory"* ]]
}

@test "tower add: no arguments still opens the picker, not the path branch" {
    # MODE stays "pick" unless a bare path arrives.
    run grep -c 'MODE="in-dir"' "$ADD"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}
