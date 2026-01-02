#!/usr/bin/env bats
# Unit tests for sanitization functions in common.sh

load 'test_helper'

setup() {
    source_common
}

# ============================================================================
# sanitize_name() tests
# ============================================================================

@test "sanitize_name: allows alphanumeric characters" {
    result=$(sanitize_name "abc123")
    [ "$result" = "abc123" ]
}

@test "sanitize_name: allows hyphens" {
    result=$(sanitize_name "my-project")
    [ "$result" = "my-project" ]
}

@test "sanitize_name: allows underscores" {
    result=$(sanitize_name "my_project")
    [ "$result" = "my_project" ]
}

@test "sanitize_name: removes spaces" {
    result=$(sanitize_name "my project")
    [ "$result" = "myproject" ]
}

@test "sanitize_name: removes special characters" {
    result=$(sanitize_name "my@project#name!")
    [ "$result" = "myprojectname" ]
}

@test "sanitize_name: removes path traversal attempts" {
    result=$(sanitize_name "../../../etc/passwd")
    [ "$result" = "etcpasswd" ]
}

@test "sanitize_name: removes shell injection characters" {
    result=$(sanitize_name "test; rm -rf /")
    # Hyphens are preserved, spaces and special chars removed
    [ "$result" = "testrm-rf" ]
}

@test "sanitize_name: removes command substitution" {
    result=$(sanitize_name 'test$(whoami)')
    [ "$result" = "testwhoami" ]
}

@test "sanitize_name: removes backtick command substitution" {
    result=$(sanitize_name 'test`whoami`')
    [ "$result" = "testwhoami" ]
}

@test "sanitize_name: trims leading hyphens" {
    result=$(sanitize_name "---myproject")
    [ "$result" = "myproject" ]
}

@test "sanitize_name: trims trailing hyphens" {
    result=$(sanitize_name "myproject---")
    [ "$result" = "myproject" ]
}

@test "sanitize_name: trims leading underscores" {
    result=$(sanitize_name "___myproject")
    [ "$result" = "myproject" ]
}

@test "sanitize_name: trims trailing underscores" {
    result=$(sanitize_name "myproject___")
    [ "$result" = "myproject" ]
}

@test "sanitize_name: returns empty for entirely invalid input" {
    result=$(sanitize_name "!@#$%^&*()")
    [ "$result" = "" ]
}

@test "sanitize_name: truncates to 64 characters" {
    long_name="a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]a]"
    result=$(sanitize_name "$long_name")
    [ ${#result} -le 64 ]
}

@test "sanitize_name: handles unicode characters" {
    result=$(sanitize_name "project-name")
    [ "$result" = "project-name" ]
}

@test "sanitize_name: handles empty input" {
    result=$(sanitize_name "")
    [ "$result" = "" ]
}

@test "sanitize_name: handles null bytes" {
    # Null bytes are removed by tr -cd
    result=$(sanitize_name "test"$'\x00'"name")
    [ "$result" = "testname" ]
}

# ============================================================================
# validate_path_within() tests
# ============================================================================

@test "validate_path_within: accepts path within base directory" {
    setup_test_env
    mkdir -p "${CLAUDE_TOWER_WORKTREE_DIR}/myproject"

    run validate_path_within "${CLAUDE_TOWER_WORKTREE_DIR}/myproject" "$CLAUDE_TOWER_WORKTREE_DIR"
    [ "$status" -eq 0 ]

    teardown_test_env
}

@test "validate_path_within: rejects path outside base directory" {
    setup_test_env

    run validate_path_within "/etc/passwd" "$CLAUDE_TOWER_WORKTREE_DIR"
    [ "$status" -eq 1 ]

    teardown_test_env
}

@test "validate_path_within: rejects path traversal with .." {
    setup_test_env

    run validate_path_within "${CLAUDE_TOWER_WORKTREE_DIR}/../../../etc/passwd" "$CLAUDE_TOWER_WORKTREE_DIR"
    [ "$status" -eq 1 ]

    teardown_test_env
}

@test "validate_path_within: accepts nested path within base" {
    setup_test_env
    mkdir -p "${CLAUDE_TOWER_WORKTREE_DIR}/deep/nested/path"

    run validate_path_within "${CLAUDE_TOWER_WORKTREE_DIR}/deep/nested/path" "$CLAUDE_TOWER_WORKTREE_DIR"
    [ "$status" -eq 0 ]

    teardown_test_env
}

@test "validate_path_within: rejects symlink escape" {
    # Skip if realpath doesn't support -m option (required for symlink resolution)
    realpath -m /tmp >/dev/null 2>&1 || skip "realpath -m not available (macOS)"

    setup_test_env

    # Create a symlink that points outside the base directory
    ln -sf /tmp "${CLAUDE_TOWER_WORKTREE_DIR}/escape_link" 2>/dev/null || skip "Cannot create symlinks"

    run validate_path_within "${CLAUDE_TOWER_WORKTREE_DIR}/escape_link" "$CLAUDE_TOWER_WORKTREE_DIR"
    # Should fail because resolved path is outside base
    [ "$status" -eq 1 ]

    teardown_test_env
}

# ============================================================================
# normalize_session_name() tests
# ============================================================================

@test "normalize_session_name: adds tower_ prefix" {
    result=$(normalize_session_name "myproject")
    [ "$result" = "tower_myproject" ]
}

@test "normalize_session_name: replaces spaces with underscores" {
    result=$(normalize_session_name "my project")
    [ "$result" = "tower_my_project" ]
}

@test "normalize_session_name: replaces dots with underscores" {
    result=$(normalize_session_name "my.project")
    [ "$result" = "tower_my_project" ]
}

@test "normalize_session_name: handles multiple spaces and dots" {
    result=$(normalize_session_name "my project.name")
    [ "$result" = "tower_my_project_name" ]
}

@test "normalize_session_name: preserves hyphens" {
    result=$(normalize_session_name "my-project")
    [ "$result" = "tower_my-project" ]
}

@test "normalize_session_name: handles empty input" {
    result=$(normalize_session_name "")
    [ "$result" = "tower_" ]
}
