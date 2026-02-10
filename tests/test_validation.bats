#!/usr/bin/env bats
# Unit tests for validation functions in common.sh

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================================================
# validate_session_name() tests
# ============================================================================

@test "validate_session_name: accepts alphanumeric name" {
    run validate_session_name "myproject123"
    [ "$status" -eq 0 ]
}

@test "validate_session_name: accepts name with hyphens" {
    run validate_session_name "my-project"
    [ "$status" -eq 0 ]
}

@test "validate_session_name: accepts name with underscores" {
    run validate_session_name "my_project"
    [ "$status" -eq 0 ]
}

@test "validate_session_name: accepts mixed valid characters" {
    run validate_session_name "My_Project-123"
    [ "$status" -eq 0 ]
}

@test "validate_session_name: rejects empty name" {
    run validate_session_name ""
    [ "$status" -eq 1 ]
}

@test "validate_session_name: rejects name with spaces" {
    run validate_session_name "my project"
    [ "$status" -eq 1 ]
}

@test "validate_session_name: rejects name with special characters" {
    run validate_session_name "my@project"
    [ "$status" -eq 1 ]
}

@test "validate_session_name: rejects name with dots" {
    run validate_session_name "my.project"
    [ "$status" -eq 1 ]
}

@test "validate_session_name: rejects name over 64 characters" {
    local long_name="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"  # 65 chars
    run validate_session_name "$long_name"
    [ "$status" -eq 1 ]
}

@test "validate_session_name: accepts name of exactly 64 characters" {
    local exact_name="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"  # 64 chars
    run validate_session_name "$exact_name"
    [ "$status" -eq 0 ]
}

# ============================================================================
# validate_path_within() edge cases
# ============================================================================

@test "validate_path_within: handles empty path" {
    run validate_path_within "" "$CLAUDE_TOWER_WORKTREE_DIR"
    [ "$status" -eq 1 ]
}

@test "validate_path_within: handles empty base directory" {
    run validate_path_within "/some/path" ""
    [ "$status" -eq 1 ]
}

@test "validate_path_within: handles path with spaces" {
    mkdir -p "${CLAUDE_TOWER_WORKTREE_DIR}/path with spaces"

    run validate_path_within "${CLAUDE_TOWER_WORKTREE_DIR}/path with spaces" "$CLAUDE_TOWER_WORKTREE_DIR"
    [ "$status" -eq 0 ]
}

@test "validate_path_within: handles path with unicode" {
    mkdir -p "${CLAUDE_TOWER_WORKTREE_DIR}/path_日本語"

    run validate_path_within "${CLAUDE_TOWER_WORKTREE_DIR}/path_日本語" "$CLAUDE_TOWER_WORKTREE_DIR"
    [ "$status" -eq 0 ]
}

@test "validate_path_within: rejects double dot in middle of path" {
    run validate_path_within "${CLAUDE_TOWER_WORKTREE_DIR}/foo/../../../etc/passwd" "$CLAUDE_TOWER_WORKTREE_DIR"
    [ "$status" -eq 1 ]
}

@test "validate_path_within: accepts same path as base" {
    run validate_path_within "$CLAUDE_TOWER_WORKTREE_DIR" "$CLAUDE_TOWER_WORKTREE_DIR"
    [ "$status" -eq 0 ]
}
