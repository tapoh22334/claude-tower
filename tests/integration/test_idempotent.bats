#!/usr/bin/env bats
# Integration tests for idempotent session operations
# These tests verify that session state detection and operations
# are idempotent and handle state inconsistencies gracefully.

load '../test_helper'

# Start a dedicated tmux server for tests
TMUX_SOCKET="claude-tower-idempotent-test-$$"

setup_file() {
    # Use /tmp for tmux sockets to avoid permission issues
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
    # Use /tmp for tmux sockets
    export TMUX_TMPDIR="/tmp/claude-tower-test-$$"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"
}

teardown() {
    # Clean up any sessions created during tests
    tmux -L "$TMUX_SOCKET" kill-session -t "tower_idem_test" 2>/dev/null || true
    tmux -L "$TMUX_SOCKET" kill-session -t "tower_active_test" 2>/dev/null || true
    tmux -L "$TMUX_SOCKET" kill-session -t "tower_dormant_test" 2>/dev/null || true
    teardown_test_env
}

# ============================================================================
# get_session_state() idempotent tests
# ============================================================================

@test "idempotent: get_session_state returns 'active' for existing tmux session" {
    # Create a real tmux session
    tmux -L "$TMUX_SOCKET" new-session -d -s "tower_active_test"

    # Override tmux to use our socket
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    result=$(get_session_state "tower_active_test")
    [ "$result" = "active" ]
}

@test "idempotent: get_session_state returns 'dormant' for session with metadata only" {
    # Override tmux to use our socket (no real session exists)
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # Create only metadata, no tmux session
    create_mock_metadata "tower_dormant_test"

    result=$(get_session_state "tower_dormant_test")
    [ "$result" = "dormant" ]
}

@test "idempotent: get_session_state returns empty for non-existent session" {
    # Override tmux to use our socket
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # No session, no metadata
    result=$(get_session_state "tower_nonexistent_xyz")
    [ -z "$result" ]
}

@test "idempotent: get_session_state never fails (exit code 0)" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # Test with non-existent session - should not fail
    run get_session_state "tower_nonexistent"
    [ "$status" -eq 0 ]

    # Test with dormant session - should not fail
    create_mock_metadata "tower_dormant_check"
    run get_session_state "tower_dormant_check"
    [ "$status" -eq 0 ]

    # Test with active session - should not fail
    tmux -L "$TMUX_SOCKET" new-session -d -s "tower_active_check"
    run get_session_state "tower_active_check"
    [ "$status" -eq 0 ]
    tmux -L "$TMUX_SOCKET" kill-session -t "tower_active_check"
}

@test "idempotent: get_session_state is consistent on repeated calls" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    create_mock_metadata "tower_consistent"

    # Call multiple times, should always return same result
    result1=$(get_session_state "tower_consistent")
    result2=$(get_session_state "tower_consistent")
    result3=$(get_session_state "tower_consistent")

    [ "$result1" = "dormant" ]
    [ "$result2" = "dormant" ]
    [ "$result3" = "dormant" ]
}

# ============================================================================
# State transition tests
# ============================================================================

@test "idempotent: state changes from dormant to active when session created" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # Start with dormant (metadata only)
    create_mock_metadata "tower_transition"
    state_before=$(get_session_state "tower_transition")
    [ "$state_before" = "dormant" ]

    # Create tmux session
    tmux -L "$TMUX_SOCKET" new-session -d -s "tower_transition"

    # Now should be active
    state_after=$(get_session_state "tower_transition")
    [ "$state_after" = "active" ]

    tmux -L "$TMUX_SOCKET" kill-session -t "tower_transition"
}

@test "idempotent: state changes from active to dormant when session killed" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # Start with active (session + metadata)
    create_mock_metadata "tower_kill_test"
    tmux -L "$TMUX_SOCKET" new-session -d -s "tower_kill_test"

    state_before=$(get_session_state "tower_kill_test")
    [ "$state_before" = "active" ]

    # Kill tmux session
    tmux -L "$TMUX_SOCKET" kill-session -t "tower_kill_test"

    # Now should be dormant (metadata still exists)
    state_after=$(get_session_state "tower_kill_test")
    [ "$state_after" = "dormant" ]
}

# ============================================================================
# list_all_sessions() idempotent tests
# ============================================================================

@test "idempotent: list_all_sessions returns empty for no sessions" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    result=$(list_all_sessions)
    [ -z "$result" ]
}

@test "idempotent: list_all_sessions includes both active and dormant" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # Create active session
    tmux -L "$TMUX_SOCKET" new-session -d -s "tower_list_active"
    create_mock_metadata "tower_list_active"

    # Create dormant session (metadata only)
    create_mock_metadata "tower_list_dormant"

    result=$(list_all_sessions)

    [[ "$result" == *"tower_list_active"* ]]
    [[ "$result" == *"tower_list_dormant"* ]]
    [[ "$result" == *"active"* ]]
    [[ "$result" == *"dormant"* ]]

    tmux -L "$TMUX_SOCKET" kill-session -t "tower_list_active"
}

@test "idempotent: list_all_sessions never fails (exit code 0)" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # Empty case
    run list_all_sessions
    [ "$status" -eq 0 ]

    # With sessions
    create_mock_metadata "tower_list_check"
    run list_all_sessions
    [ "$status" -eq 0 ]
}

# ============================================================================
# has_metadata() idempotent tests
# ============================================================================

@test "idempotent: has_metadata is idempotent for existing metadata" {
    create_mock_metadata "tower_meta_exists"

    # Multiple calls should always succeed
    run has_metadata "tower_meta_exists"
    [ "$status" -eq 0 ]
    run has_metadata "tower_meta_exists"
    [ "$status" -eq 0 ]
}

@test "idempotent: has_metadata is idempotent for non-existing metadata" {
    # Multiple calls should always fail (consistently)
    run has_metadata "tower_meta_nonexistent"
    [ "$status" -eq 1 ]
    run has_metadata "tower_meta_nonexistent"
    [ "$status" -eq 1 ]
}

# ============================================================================
# Edge cases
# ============================================================================

@test "idempotent: handles session with spaces in name" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # Note: tmux doesn't allow spaces in session names, but we should handle gracefully
    result=$(get_session_state "tower_space name")
    [ -z "$result" ]
}

@test "idempotent: handles empty session name" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    result=$(get_session_state "")
    [ -z "$result" ]
}

@test "idempotent: handles special characters in session name" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # These should not cause errors, just return empty
    run get_session_state "tower_test;echo"
    [ "$status" -eq 0 ]

    run get_session_state "tower_test|cat"
    [ "$status" -eq 0 ]
}
