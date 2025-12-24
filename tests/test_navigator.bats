#!/usr/bin/env bats
# Unit tests for navigator.sh functions

load 'test_helper'

setup() {
    source_common
}

# ============================================================================
# Session state detection tests
# ============================================================================

@test "get_session_state: returns dormant for session with metadata but no tmux session" {
    setup_test_env
    create_mock_metadata "tower_test-session"

    run get_session_state "tower_test-session"

    [ "$status" -eq 0 ]
    [ "$output" = "dormant" ]

    teardown_test_env
}

@test "get_session_state: returns empty for non-existent session" {
    setup_test_env

    run get_session_state "tower_nonexistent"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]

    teardown_test_env
}

@test "get_state_icon: returns correct icon for running" {
    run get_state_icon "running"

    [ "$status" -eq 0 ]
    [ "$output" = "◉" ]
}

@test "get_state_icon: returns correct icon for idle" {
    run get_state_icon "idle"

    [ "$status" -eq 0 ]
    [ "$output" = "▶" ]
}

@test "get_state_icon: returns correct icon for exited" {
    run get_state_icon "exited"

    [ "$status" -eq 0 ]
    [ "$output" = "!" ]
}

@test "get_state_icon: returns correct icon for dormant" {
    run get_state_icon "dormant"

    [ "$status" -eq 0 ]
    [ "$output" = "○" ]
}

# ============================================================================
# Session type tests
# ============================================================================

@test "get_type_icon: returns [W] for worktree" {
    run get_type_icon "worktree"

    [ "$status" -eq 0 ]
    [ "$output" = "[W]" ]
}

@test "get_type_icon: returns [S] for simple" {
    run get_type_icon "simple"

    [ "$status" -eq 0 ]
    [ "$output" = "[S]" ]
}

@test "get_session_type: returns worktree for metadata with workspace type" {
    setup_test_env
    create_mock_metadata "tower_test-session" "workspace"

    run get_session_type "tower_test-session"

    [ "$status" -eq 0 ]
    [ "$output" = "worktree" ]

    teardown_test_env
}

@test "get_session_type: returns simple for session without metadata" {
    setup_test_env

    run get_session_type "tower_nonexistent"

    [ "$status" -eq 0 ]
    [ "$output" = "simple" ]

    teardown_test_env
}

# ============================================================================
# list_all_sessions tests
# ============================================================================

@test "list_all_sessions: includes dormant sessions from metadata" {
    setup_test_env
    create_mock_metadata "tower_dormant-session" "workspace"

    run list_all_sessions

    [ "$status" -eq 0 ]
    [[ "$output" == *"tower_dormant-session"* ]]

    teardown_test_env
}

@test "list_all_sessions: output format includes session_id:state:type" {
    setup_test_env
    create_mock_metadata "tower_test-session" "workspace"

    run list_all_sessions

    [ "$status" -eq 0 ]
    [[ "$output" == *":"* ]]

    teardown_test_env
}
