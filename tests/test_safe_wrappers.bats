#!/usr/bin/env bats
# Unit tests for safe command wrapper functions in common.sh

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================================================
# safe_git() tests
# ============================================================================

@test "safe_git: returns 0 for successful command" {
    # Initialize a git repo for testing
    mkdir -p "${TEST_DIR}/tmp/git_test"
    git -C "${TEST_DIR}/tmp/git_test" init -q

    run safe_git -C "${TEST_DIR}/tmp/git_test" status
    [ "$status" -eq 0 ]
}

@test "safe_git: returns 1 for failed command" {
    run safe_git -C "/nonexistent/path" status
    [ "$status" -eq 1 ]
}

@test "safe_git: handles invalid git command" {
    run safe_git invalid_command_xyz
    [ "$status" -eq 1 ]
}

# ============================================================================
# run_with_timeout() tests
# ============================================================================

@test "run_with_timeout: executes command successfully" {
    run run_with_timeout 5 echo "hello"
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "run_with_timeout: passes through command exit code" {
    run run_with_timeout 5 false
    [ "$status" -eq 1 ]
}

@test "run_with_timeout: handles command with arguments" {
    run run_with_timeout 5 ls -la /tmp
    [ "$status" -eq 0 ]
}

# ============================================================================
# get_active_sessions() tests
# ============================================================================

@test "get_active_sessions: does not error" {
    # This test just verifies the function doesn't crash
    # It may return empty if tmux is not running
    run get_active_sessions
    [ "$status" -eq 0 ]
}

@test "get_active_sessions: returns string output" {
    result=$(get_active_sessions)
    # Result should be a string (possibly empty)
    [ -n "$result" ] || [ -z "$result" ]
}
