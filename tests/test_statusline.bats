#!/usr/bin/env bats
# Smoke tests for statusline.sh — verify it runs without error in all modes,
# emits sensible output, and degrades gracefully when there's no tmux session
# or no metadata. Does not assert on visual layout.

load 'test_helper'

STATUSLINE="$PROJECT_ROOT/tmux-plugin/scripts/statusline.sh"

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Mode dispatch — each entry point must exit 0
# ============================================================================

@test "statusline.sh is executable" {
    [ -x "$STATUSLINE" ]
}

@test "statusline session mode exits 0 even without tmux" {
    # No TMUX env — get_session_info should return empty silently
    run env -u TMUX "$STATUSLINE" session
    [ "$status" -eq 0 ]
}

@test "statusline stats mode exits 0 with no metadata files" {
    # Fresh metadata dir, no .meta files
    run env -u TMUX "$STATUSLINE" stats
    [ "$status" -eq 0 ]
    # Stats output should contain the prefix glyph or counter format
    [[ "$output" == *"0"* ]]
}

@test "statusline full mode exits 0 and emits at least the separator" {
    run env -u TMUX "$STATUSLINE" full
    [ "$status" -eq 0 ]
    [[ "$output" == *"│"* ]]
}

@test "statusline default mode (no arg) equals full mode" {
    local default_output full_output
    default_output=$(env -u TMUX "$STATUSLINE")
    full_output=$(env -u TMUX "$STATUSLINE" full)
    [ "$default_output" = "$full_output" ]
}

@test "statusline unknown mode falls through to full output" {
    # The case is 'full | *)' so unknown mode hits full
    run env -u TMUX "$STATUSLINE" some-unknown-mode
    [ "$status" -eq 0 ]
}

# ============================================================================
# Stats counting — active vs dormant
# ============================================================================

@test "statusline stats counts dormant sessions from metadata files" {
    # Create 2 dormant sessions (metadata only, no tmux session)
    save_metadata "tower_stats_dormant_a" "/tmp"
    save_metadata "tower_stats_dormant_b" "/tmp"

    run env -u TMUX "$STATUSLINE" stats
    [ "$status" -eq 0 ]
    # Output format: "...▶active/○dormant..."; we just check both digits appear
    # With 2 dormant and 0 active, expect a '2' somewhere in the count area
    [[ "$output" == *"2"* ]]
}

@test "statusline stats handles empty metadata directory gracefully" {
    # Ensure metadata dir is empty for this test
    rm -f "$CLAUDE_TOWER_METADATA_DIR"/*.meta 2>/dev/null
    run env -u TMUX "$STATUSLINE" stats
    [ "$status" -eq 0 ]
    [[ "$output" == *"0"* ]]
}

# ============================================================================
# Non-crash guarantees for the renderer
# ============================================================================

@test "statusline does not error when metadata dir does not exist" {
    # Point to a non-existent directory
    CLAUDE_TOWER_METADATA_DIR="/tmp/nonexistent-tower-statusline-$$" \
        run env -u TMUX "$STATUSLINE" stats
    [ "$status" -eq 0 ]
}

@test "statusline output does not contain raw error keywords" {
    run env -u TMUX "$STATUSLINE" full
    [ "$status" -eq 0 ]
    # Stderr-only error messages would still be captured by 'run'; we assert
    # no leak of stack traces or bash errors into stdout.
    ! [[ "$output" == *"command not found"* ]]
    ! [[ "$output" == *"unbound variable"* ]]
    ! [[ "$output" == *"syntax error"* ]]
}
