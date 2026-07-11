#!/usr/bin/env bats
# Automated scenario tests
# Wraps scenario markdown files as bats tests

load '../test_helper'

SCENARIO_DIR="$BATS_TEST_DIRNAME"

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Scenario: Basic Session Creation (01_basic_session.md)
# ============================================================================

@test "scenario-01: create temporary test directory" {
    TEST_DIR=$(mktemp -d)
    [ -d "$TEST_DIR" ]
    rm -rf "$TEST_DIR"
}

@test "scenario-01: source common library succeeds" {
    run source_common
    [ "$status" -eq 0 ]
}

@test "scenario-01: create simple session manually" {
    local SESSION_NAME="scenario-test-simple-$$"
    local SESSION_ID="tower_${SESSION_NAME}"
    local TMUX_SOCKET="scenario-test-$$"

    # Create tmux session
    tmux -L "$TMUX_SOCKET" new-session -d -s "$SESSION_ID" -c /tmp

    # Save metadata (minimal registry: session_name + created_at only)
    save_metadata "$SESSION_ID" "$SESSION_NAME"

    # Verify session exists
    run tmux -L "$TMUX_SOCKET" has-session -t "$SESSION_ID"
    [ "$status" -eq 0 ]

    # Verify metadata was saved
    [ -f "${CLAUDE_TOWER_METADATA_DIR}/${SESSION_ID}.meta" ]
    grep -q "session_name=${SESSION_NAME}" "${CLAUDE_TOWER_METADATA_DIR}/${SESSION_ID}.meta"

    # Cleanup
    tmux -L "$TMUX_SOCKET" kill-session -t "$SESSION_ID"
    rm -f "${CLAUDE_TOWER_METADATA_DIR}/${SESSION_ID}.meta"
    tmux -L "$TMUX_SOCKET" kill-server 2>/dev/null || true
}

# ============================================================================
# Scenario: Navigator Navigation
# ============================================================================

@test "scenario-nav: j/k navigation changes selection state" {
    local SESSIONS=("tower_nav_a" "tower_nav_b" "tower_nav_c")

    ensure_nav_state_dir

    # Start at first session
    set_nav_selected "tower_nav_a"

    # Simulate 'j' (down)
    local current_index=0
    local new_index=$((current_index + 1))
    set_nav_selected "${SESSIONS[$new_index]}"

    result=$(get_nav_selected)
    [ "$result" = "tower_nav_b" ]

    # Simulate 'k' (up)
    current_index=1
    new_index=$((current_index - 1))
    set_nav_selected "${SESSIONS[$new_index]}"

    result=$(get_nav_selected)
    [ "$result" = "tower_nav_a" ]

    cleanup_nav_state
}

@test "scenario-nav: g jumps to first, G jumps to last" {
    local SESSIONS=("tower_nav_a" "tower_nav_b" "tower_nav_c")

    ensure_nav_state_dir

    # Start in middle
    set_nav_selected "tower_nav_b"

    # Simulate 'g' (first)
    set_nav_selected "${SESSIONS[0]}"
    result=$(get_nav_selected)
    [ "$result" = "tower_nav_a" ]

    # Simulate 'G' (last)
    set_nav_selected "${SESSIONS[-1]}"
    result=$(get_nav_selected)
    [ "$result" = "tower_nav_c" ]

    cleanup_nav_state
}

@test "scenario-nav: i switches focus to view" {
    ensure_nav_state_dir

    set_nav_focus "list"
    [ "$(get_nav_focus)" = "list" ]

    # Simulate 'i' (view mode)
    set_nav_focus "view"
    [ "$(get_nav_focus)" = "view" ]

    cleanup_nav_state
}

# ============================================================================
# Scenario: Session Lifecycle
# ============================================================================

@test "scenario-lifecycle: dormant detection with metadata-only" {
    local SESSION_ID="tower_dormant_test_$$"

    # Create metadata without tmux session
    create_mock_metadata "$SESSION_ID"

    # Override tmux to use a non-existent socket
    local TMUX_SOCKET="nonexistent-$$"
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # Should be detected as dormant
    run get_session_state "$SESSION_ID"
    [ "$status" -eq 0 ]
    [ "$output" = "dormant" ]
}

@test "scenario-lifecycle: delete_metadata removes registry entry" {
    local SESSION_ID="tower_cleanup_test_$$"

    save_metadata "$SESSION_ID" "cleanup-test"

    # Verify setup
    [ -f "${CLAUDE_TOWER_METADATA_DIR}/${SESSION_ID}.meta" ]

    # Cleanup
    delete_metadata "$SESSION_ID"

    # Verify cleanup
    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/${SESSION_ID}.meta" ]
}

# ============================================================================
# Scenario: Error Handling
# ============================================================================

@test "scenario-error: invalid session name rejected" {
    run validate_session_name ""
    [ "$status" -eq 1 ]

    run validate_session_name "$(printf 'a%.0s' {1..100})"
    [ "$status" -eq 1 ]

    run validate_session_name "test/slash"
    [ "$status" -eq 1 ]
}

@test "scenario-error: command injection prevented" {
    run validate_tower_session_id "tower_; rm -rf /"
    [ "$status" -eq 1 ]

    run validate_tower_session_id 'tower_$(whoami)'
    [ "$status" -eq 1 ]

    run sanitize_name "../../../etc/passwd"
    [[ "$output" != *".."* ]]
    [[ "$output" != *"/"* ]]
}

@test "scenario-error: path traversal blocked" {
    run validate_path_within "/tmp/../etc/passwd" "/tmp"
    [ "$status" -eq 1 ]

    run validate_path_within "/tmp/safe/file" "/tmp"
    [ "$status" -eq 0 ]
}
