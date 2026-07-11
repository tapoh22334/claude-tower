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
# worktree_exists() tests
# ============================================================================

@test "worktree_exists: returns false for non-existent path" {
    run worktree_exists "/nonexistent/path"
    [ "$status" -eq 1 ]
}

@test "worktree_exists: returns false for empty directory" {
    mkdir -p "${TEST_DIR}/tmp/pathbase/empty"

    run worktree_exists "${TEST_DIR}/tmp/pathbase/empty"
    [ "$status" -eq 1 ]
}

@test "worktree_exists: returns true for directory with .git file" {
    mkdir -p "${TEST_DIR}/tmp/pathbase/with_git_file"
    echo "gitdir: /some/path" > "${TEST_DIR}/tmp/pathbase/with_git_file/.git"

    run worktree_exists "${TEST_DIR}/tmp/pathbase/with_git_file"
    [ "$status" -eq 0 ]
}

@test "worktree_exists: returns true for directory with .git directory" {
    mkdir -p "${TEST_DIR}/tmp/pathbase/with_git_dir/.git"

    run worktree_exists "${TEST_DIR}/tmp/pathbase/with_git_dir"
    [ "$status" -eq 0 ]
}

# ============================================================================
# validate_path_within() edge cases
# ============================================================================

@test "validate_path_within: handles empty path" {
    run validate_path_within "" "${TEST_DIR}/tmp/pathbase"
    [ "$status" -eq 1 ]
}

@test "validate_path_within: handles empty base directory" {
    run validate_path_within "/some/path" ""
    [ "$status" -eq 1 ]
}

@test "validate_path_within: handles path with spaces" {
    mkdir -p "${TEST_DIR}/tmp/pathbase/path with spaces"

    run validate_path_within "${TEST_DIR}/tmp/pathbase/path with spaces" "${TEST_DIR}/tmp/pathbase"
    [ "$status" -eq 0 ]
}

@test "validate_path_within: handles path with unicode" {
    mkdir -p "${TEST_DIR}/tmp/pathbase/path_日本語"

    run validate_path_within "${TEST_DIR}/tmp/pathbase/path_日本語" "${TEST_DIR}/tmp/pathbase"
    [ "$status" -eq 0 ]
}

@test "validate_path_within: rejects double dot in middle of path" {
    run validate_path_within "${TEST_DIR}/tmp/pathbase/foo/../../../etc/passwd" "${TEST_DIR}/tmp/pathbase"
    [ "$status" -eq 1 ]
}

@test "validate_path_within: accepts same path as base" {
    run validate_path_within "${TEST_DIR}/tmp/pathbase" "${TEST_DIR}/tmp/pathbase"
    [ "$status" -eq 0 ]
}
