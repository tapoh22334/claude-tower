#!/usr/bin/env bats
# Unit tests for dependency checking functions in common.sh

load 'test_helper'

setup() {
    source_common
}

# ============================================================================
# require_command() tests
# ============================================================================

@test "require_command: succeeds for existing command (bash)" {
    run require_command "bash"
    [ "$status" -eq 0 ]
}

@test "require_command: succeeds for existing command (ls)" {
    run require_command "ls"
    [ "$status" -eq 0 ]
}

@test "require_command: fails for non-existent command" {
    run require_command "nonexistent_command_xyz_123_456"
    [ "$status" -eq 1 ]
}

@test "require_command: outputs error message for missing command" {
    run require_command "nonexistent_command_xyz"
    # Error message contains the command name
    [[ "$output" == *"nonexistent_command_xyz"* ]]
}

@test "require_command: shows install hint for known commands" {
    run require_command "fzf_nonexistent"
    # Should fail but not crash
    [ "$status" -eq 1 ]
}

# ============================================================================
# ensure_metadata_dir() tests
# ============================================================================

@test "ensure_metadata_dir: creates directory if not exists" {
    setup_test_env
    rm -rf "$CLAUDE_TOWER_METADATA_DIR"

    ensure_metadata_dir

    [ -d "$CLAUDE_TOWER_METADATA_DIR" ]
    teardown_test_env
}

@test "ensure_metadata_dir: succeeds when directory already exists" {
    setup_test_env

    ensure_metadata_dir
    ensure_metadata_dir  # Call twice

    [ -d "$CLAUDE_TOWER_METADATA_DIR" ]
    teardown_test_env
}

@test "ensure_metadata_dir: creates parent directories" {
    # Run in subshell with custom CLAUDE_TOWER_METADATA_DIR set before sourcing
    local deep_dir="${BATS_TEST_TMPDIR}/deep/nested/metadata"
    run bash -c "
        export CLAUDE_TOWER_METADATA_DIR='$deep_dir'
        source '$PROJECT_ROOT/tmux-plugin/lib/common.sh' 2>/dev/null
        ensure_metadata_dir
        [ -d '$deep_dir' ]
    "
    [ "$status" -eq 0 ]
}
