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
    # Set session socket and TMUX_TMPDIR BEFORE sourcing common.sh
    export CLAUDE_TOWER_SESSION_SOCKET="$TMUX_SOCKET"
    export TMUX_TMPDIR="/tmp/claude-tower-test-$$"
    mkdir -p "$TMUX_TMPDIR" 2>/dev/null || true
    chmod 700 "$TMUX_TMPDIR" 2>/dev/null || true
    source_common
    setup_test_env
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
    # Create a test session (session_tmux uses TOWER_SESSION_SOCKET set in setup)
    session_tmux new-session -d -s "tower_exists_test"

    run session_exists "tower_exists_test"
    [ "$status" -eq 0 ]

    session_tmux kill-session -t "tower_exists_test"
}

@test "integration: session_exists returns false for non-existing session" {
    run session_exists "tower_nonexistent_xyz"
    [ "$status" -eq 1 ]
}

# ============================================================================
# get_active_sessions() tests with real tmux
# ============================================================================

@test "integration: get_active_sessions lists sessions" {
    # Create test sessions
    session_tmux new-session -d -s "tower_list1"
    session_tmux new-session -d -s "tower_list2"

    result=$(get_active_sessions)

    [[ "$result" == *"tower_list1"* ]]
    [[ "$result" == *"tower_list2"* ]]

    session_tmux kill-session -t "tower_list1"
    session_tmux kill-session -t "tower_list2"
}

# ============================================================================
# safe_tmux() tests with real tmux
# ============================================================================

@test "integration: safe_tmux creates session" {
    # safe_tmux uses plain tmux, so override to route to test socket
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    run safe_tmux new-session -d -s "tower_safe_test"
    [ "$status" -eq 0 ]

    # Verify session exists
    run session_tmux has-session -t "tower_safe_test"
    [ "$status" -eq 0 ]

    session_tmux kill-session -t "tower_safe_test"
}

@test "integration: safe_tmux fails gracefully for invalid command" {
    run safe_tmux invalid-command-xyz
    [ "$status" -eq 1 ]
}

# ============================================================================
# tmux option storage tests
# ============================================================================

@test "integration: can store and retrieve session options" {
    # Create session
    session_tmux new-session -d -s "tower_options_test"

    # Store option
    session_tmux set-option -t "tower_options_test" @tower_session_type "workspace"

    # Retrieve option
    result=$(session_tmux show-option -t "tower_options_test" -v @tower_session_type 2>/dev/null || echo "")

    [ "$result" = "workspace" ]

    session_tmux kill-session -t "tower_options_test"
}

@test "integration: session options persist during session lifetime" {
    session_tmux new-session -d -s "tower_persist_test"

    # Store multiple options
    session_tmux set-option -t "tower_persist_test" @tower_session_type "workspace"
    session_tmux set-option -t "tower_persist_test" @tower_repository "/test/repo"
    session_tmux set-option -t "tower_persist_test" @tower_source "abc123"

    # Verify all options
    type_val=$(session_tmux show-option -t "tower_persist_test" -v @tower_session_type)
    repo_val=$(session_tmux show-option -t "tower_persist_test" -v @tower_repository)
    source_val=$(session_tmux show-option -t "tower_persist_test" -v @tower_source)

    [ "$type_val" = "workspace" ]
    [ "$repo_val" = "/test/repo" ]
    [ "$source_val" = "abc123" ]

    session_tmux kill-session -t "tower_persist_test"
}

# ============================================================================
# Orphan detection with real tmux
# ============================================================================

@test "integration: find_orphaned_metadata detects sessions not in tmux" {
    # Create metadata for sessions
    create_mock_metadata "tower_active_int"
    create_mock_metadata "tower_orphan_int"

    # Only create tmux session for "active"
    session_tmux new-session -d -s "tower_active_int"

    # Find orphaned metadata
    orphans=$(find_orphaned_metadata)

    [[ "$orphans" == *"tower_orphan_int"* ]]
    [[ "$orphans" != *"tower_active_int"* ]]

    session_tmux kill-session -t "tower_active_int"
}
