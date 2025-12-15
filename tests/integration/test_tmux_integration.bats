#!/usr/bin/env bats
# Integration tests for tmux interaction
# These tests require a real tmux server to be running

load '../test_helper'

# Start a dedicated tmux server for tests
TMUX_SOCKET="claude-tower-test-$$"

setup_file() {
    # Use /tmp for tmux sockets to avoid WSL permission issues
    export TMUX_TMPDIR="/tmp/claude-tower-test-$$"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"
    # Start a new tmux server for testing
    tmux -L "$TMUX_SOCKET" new-session -d -s "test-base" 2>/dev/null || true
}

teardown_file() {
    # Kill the test tmux server
    tmux -L "$TMUX_SOCKET" kill-server 2>/dev/null || true
    # Clean up tmux socket directory
    rm -rf "/tmp/claude-tower-test-$$" 2>/dev/null || true
}

setup() {
    source_common
    setup_test_env
    # Use /tmp for tmux sockets to avoid WSL permission issues
    export TMUX_TMPDIR="/tmp/claude-tower-test-$$"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"
}

teardown() {
    # Clean up any sessions created during tests
    tmux -L "$TMUX_SOCKET" kill-session -t "tower_test" 2>/dev/null || true
    teardown_test_env
}

# ============================================================================
# session_exists() tests with real tmux
# ============================================================================

@test "integration: session_exists returns true for existing session" {
    # Create a test session
    tmux -L "$TMUX_SOCKET" new-session -d -s "tower_exists_test"

    # Override tmux to use our socket
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    run session_exists "tower_exists_test"
    [ "$status" -eq 0 ]

    tmux -L "$TMUX_SOCKET" kill-session -t "tower_exists_test"
}

@test "integration: session_exists returns false for non-existing session" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    run session_exists "tower_nonexistent_xyz"
    [ "$status" -eq 1 ]
}

# ============================================================================
# get_active_sessions() tests with real tmux
# ============================================================================

@test "integration: get_active_sessions lists sessions" {
    # Create test sessions
    tmux -L "$TMUX_SOCKET" new-session -d -s "tower_list1"
    tmux -L "$TMUX_SOCKET" new-session -d -s "tower_list2"

    # Override tmux
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    result=$(get_active_sessions)

    [[ "$result" == *"tower_list1"* ]]
    [[ "$result" == *"tower_list2"* ]]

    tmux -L "$TMUX_SOCKET" kill-session -t "tower_list1"
    tmux -L "$TMUX_SOCKET" kill-session -t "tower_list2"
}

# ============================================================================
# safe_tmux() tests with real tmux
# ============================================================================

@test "integration: safe_tmux creates session" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    run safe_tmux new-session -d -s "tower_safe_test"
    [ "$status" -eq 0 ]

    # Verify session exists
    run tmux -L "$TMUX_SOCKET" has-session -t "tower_safe_test"
    [ "$status" -eq 0 ]

    tmux -L "$TMUX_SOCKET" kill-session -t "tower_safe_test"
}

@test "integration: safe_tmux fails gracefully for invalid command" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    run safe_tmux invalid-command-xyz
    [ "$status" -eq 1 ]
}

# ============================================================================
# tmux option storage tests
# ============================================================================

@test "integration: can store and retrieve session options" {
    # Create session
    tmux -L "$TMUX_SOCKET" new-session -d -s "tower_options_test"

    # Store option
    tmux -L "$TMUX_SOCKET" set-option -t "tower_options_test" @tower_session_type "workspace"

    # Retrieve option
    result=$(tmux -L "$TMUX_SOCKET" show-option -t "tower_options_test" -v @tower_session_type 2>/dev/null || echo "")

    [ "$result" = "workspace" ]

    tmux -L "$TMUX_SOCKET" kill-session -t "tower_options_test"
}

@test "integration: session options persist during session lifetime" {
    tmux -L "$TMUX_SOCKET" new-session -d -s "tower_persist_test"

    # Store multiple options
    tmux -L "$TMUX_SOCKET" set-option -t "tower_persist_test" @tower_session_type "workspace"
    tmux -L "$TMUX_SOCKET" set-option -t "tower_persist_test" @tower_repository "/test/repo"
    tmux -L "$TMUX_SOCKET" set-option -t "tower_persist_test" @tower_source "abc123"

    # Verify all options
    type_val=$(tmux -L "$TMUX_SOCKET" show-option -t "tower_persist_test" -v @tower_session_type)
    repo_val=$(tmux -L "$TMUX_SOCKET" show-option -t "tower_persist_test" -v @tower_repository)
    source_val=$(tmux -L "$TMUX_SOCKET" show-option -t "tower_persist_test" -v @tower_source)

    [ "$type_val" = "workspace" ]
    [ "$repo_val" = "/test/repo" ]
    [ "$source_val" = "abc123" ]

    tmux -L "$TMUX_SOCKET" kill-session -t "tower_persist_test"
}

# ============================================================================
# Orphan detection with real tmux
# ============================================================================

@test "integration: find_orphaned_worktrees detects sessions not in tmux" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # Create metadata for sessions
    create_mock_metadata "tower_active_int"
    create_mock_metadata "tower_orphan_int"

    # Only create tmux session for "active"
    tmux -L "$TMUX_SOCKET" new-session -d -s "tower_active_int"

    # Find orphans
    orphans=$(find_orphaned_worktrees)

    [[ "$orphans" == *"tower_orphan_int"* ]]
    [[ "$orphans" != *"tower_active_int"* ]]

    tmux -L "$TMUX_SOCKET" kill-session -t "tower_active_int"
}
