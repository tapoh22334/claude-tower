#!/usr/bin/env bats
# CLI surface contract: tower CLI rejects removed commands and shows only the
# current help text. See specs/003-simplify/contracts/tower-cli.md.

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
TOWER="$PROJECT_ROOT/tmux-plugin/bin/tower"

@test "tower binary is executable" {
    [ -x "$TOWER" ]
}

@test "tower help: documents the keeper commands" {
    run "$TOWER" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"add <path>"* ]]
    [[ "$output" == *"rm <name>"* ]]
    [[ "$output" == *"list"* ]]
    [[ "$output" == *"restore"* ]]
}

@test "tower help: 'tile' is not advertised as a subcommand" {
    run "$TOWER" help
    [ "$status" -eq 0 ]
    # The word 'tile' should not appear as a subcommand line.
    # It may appear in the trailing note ("Tile view is reachable from Navigator with Tab.").
    ! echo "$output" | grep -qE '^\s*tile\s'
}

@test "tower help: restore does not show per-id form" {
    run "$TOWER" help
    [ "$status" -eq 0 ]
    # No documented 'restore <session_id>' form
    ! echo "$output" | grep -qE 'restore\s+<.*id'
}

@test "tower tile: rejected as unknown command" {
    run "$TOWER" tile
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown command"* ]] || [[ "$output" == *"tile"* ]]
}

@test "tower restore <id>: ignores id (treated as --all)" {
    # The CLI silently treats any arg as --all per contracts/tower-cli.md.
    # We assert it does not error out with "Unknown command" — the actual restore
    # may exit non-zero if no dormant sessions exist; that's fine.
    run "$TOWER" restore some-bogus-id-that-does-not-exist
    # Must NOT match the "Unknown command" failure mode.
    ! [[ "$output" == *"Unknown command"* ]]
}
