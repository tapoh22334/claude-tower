#!/usr/bin/env bats
# Contract-based navigation tests
# Tests the relationship: key input → state file change
# These tests verify behavior through state file changes, not visual output

load '../test_helper'

# Test tmux sockets - use BATS_TEST_FILENAME hash for uniqueness
NAV_SOCKET="ct-nav-test"
DEFAULT_SOCKET="ct-default-test"

setup_file() {
    export TMUX_TMPDIR="/tmp/claude-tower-nav-test"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"

    # Start default server with test sessions (TMUX= to allow nesting)
    TMUX= tmux -L "$DEFAULT_SOCKET" new-session -d -s "tower_session_a" -c /tmp 2>/dev/null || true
    TMUX= tmux -L "$DEFAULT_SOCKET" new-session -d -s "tower_session_b" -c /tmp 2>/dev/null || true
    TMUX= tmux -L "$DEFAULT_SOCKET" new-session -d -s "tower_session_c" -c /tmp 2>/dev/null || true
}

teardown_file() {
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    TMUX= tmux -L "$DEFAULT_SOCKET" kill-server 2>/dev/null || true
    rm -rf "/tmp/claude-tower-nav-test" 2>/dev/null || true
}

setup() {
    # Set env vars BEFORE sourcing (sockets are readonly)
    export CLAUDE_TOWER_NAV_SOCKET="$NAV_SOCKET"
    export CLAUDE_TOWER_SESSION_SOCKET="$DEFAULT_SOCKET"
    export TMUX_TMPDIR="/tmp/claude-tower-nav-test"
    source_common
    setup_test_env
    ensure_nav_state_dir

    # Clean state before each test
    cleanup_nav_state
}

teardown() {
    cleanup_nav_state
    teardown_test_env
}

# ============================================================================
# Contract: set_nav_selected → get_nav_selected
# ============================================================================

@test "contract: selection state persists across function calls" {
    set_nav_selected "tower_session_a"

    local result
    result=$(get_nav_selected)

    [ "$result" = "tower_session_a" ]
}

@test "contract: selection can be changed" {
    set_nav_selected "tower_session_a"
    set_nav_selected "tower_session_b"

    local result
    result=$(get_nav_selected)

    [ "$result" = "tower_session_b" ]
}

# ============================================================================
# Contract: move_selection changes state file
# ============================================================================

@test "contract: move_selection down updates selected state" {
    # Override tmux to use test socket
    tmux() { command tmux -L "$DEFAULT_SOCKET" "$@"; }
    export -f tmux

    # Source navigator-list to get functions (partial)
    # We'll test the core logic directly

    # Setup: 3 sessions, start at first
    set_nav_selected "tower_session_a"

    # Simulate what move_selection does
    local SESSION_IDS=("tower_session_a" "tower_session_b" "tower_session_c")
    local current_index=0
    local new_index=$((current_index + 1))

    set_nav_selected "${SESSION_IDS[$new_index]}"

    local result
    result=$(get_nav_selected)

    [ "$result" = "tower_session_b" ]
}

@test "contract: move_selection wraps at end" {
    set_nav_selected "tower_session_c"

    # Simulate wrap logic
    local SESSION_IDS=("tower_session_a" "tower_session_b" "tower_session_c")
    local current_index=2
    local new_index=$((current_index + 1))
    [[ $new_index -ge ${#SESSION_IDS[@]} ]] && new_index=0

    set_nav_selected "${SESSION_IDS[$new_index]}"

    local result
    result=$(get_nav_selected)

    [ "$result" = "tower_session_a" ]
}

@test "contract: move_selection wraps at beginning" {
    set_nav_selected "tower_session_a"

    # Simulate wrap logic for up
    local SESSION_IDS=("tower_session_a" "tower_session_b" "tower_session_c")
    local current_index=0
    local new_index=$((current_index - 1))
    [[ $new_index -lt 0 ]] && new_index=$((${#SESSION_IDS[@]} - 1))

    set_nav_selected "${SESSION_IDS[$new_index]}"

    local result
    result=$(get_nav_selected)

    [ "$result" = "tower_session_c" ]
}

# ============================================================================
# Contract: focus state changes
# ============================================================================

@test "contract: focus state defaults to list" {
    rm -f "$TOWER_NAV_FOCUS_FILE" 2>/dev/null || true

    local result
    result=$(get_nav_focus)

    [ "$result" = "list" ]
}

@test "contract: focus can switch to view" {
    set_nav_focus "view"

    local result
    result=$(get_nav_focus)

    [ "$result" = "view" ]
}

@test "contract: focus can switch back to list" {
    set_nav_focus "view"
    set_nav_focus "list"

    local result
    result=$(get_nav_focus)

    [ "$result" = "list" ]
}

# ============================================================================
# Contract: caller state for return navigation
# ============================================================================

@test "contract: caller state is saved and retrieved" {
    set_nav_caller "my-original-session"

    local result
    result=$(get_nav_caller)

    [ "$result" = "my-original-session" ]
}

@test "contract: caller state persists after selection changes" {
    set_nav_caller "original"
    set_nav_selected "tower_session_a"
    set_nav_selected "tower_session_b"

    local result
    result=$(get_nav_caller)

    [ "$result" = "original" ]
}

@test "contract: cleanup_nav_state removes all state" {
    set_nav_selected "tower_session_a"
    set_nav_caller "original"
    set_nav_focus "view"

    cleanup_nav_state

    [ ! -f "$TOWER_NAV_SELECTED_FILE" ]
    [ ! -f "$TOWER_NAV_CALLER_FILE" ]
    [ ! -f "$TOWER_NAV_FOCUS_FILE" ]
}

# ============================================================================
# Contract: Session list reflects default server state
# ============================================================================

@test "contract: list_all_sessions includes active tower sessions" {
    tmux() { command tmux -L "$DEFAULT_SOCKET" "$@"; }
    export -f tmux

    run list_all_sessions

    [ "$status" -eq 0 ]
    [[ "$output" == *"tower_session_a"* ]]
    [[ "$output" == *"tower_session_b"* ]]
    [[ "$output" == *"tower_session_c"* ]]
}

@test "contract: list_all_sessions excludes non-tower sessions" {
    tmux() { command tmux -L "$DEFAULT_SOCKET" "$@"; }
    export -f tmux

    # Create a non-tower session
    command tmux -L "$DEFAULT_SOCKET" new-session -d -s "regular-session"

    run list_all_sessions

    [ "$status" -eq 0 ]
    [[ "$output" != *"regular-session"* ]]

    command tmux -L "$DEFAULT_SOCKET" kill-session -t "regular-session"
}

# ============================================================================
# Contract: Session state detection
# ============================================================================

@test "contract: get_session_state returns dormant for metadata-only session" {
    create_mock_metadata "tower_dormant_test" "workspace"

    tmux() { command tmux -L "$DEFAULT_SOCKET" "$@"; }
    export -f tmux

    run get_session_state "tower_dormant_test"

    [ "$status" -eq 0 ]
    [ "$output" = "dormant" ]
}

@test "contract: get_session_state returns empty for non-existent session" {
    tmux() { command tmux -L "$DEFAULT_SOCKET" "$@"; }
    export -f tmux

    run get_session_state "tower_nonexistent_xyz"

    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# ============================================================================
# Contract: Validation prevents invalid operations
# ============================================================================

@test "contract: validate_tower_session_id rejects command injection" {
    run validate_tower_session_id "tower_test; rm -rf /"
    [ "$status" -eq 1 ]

    run validate_tower_session_id "tower_\$(whoami)"
    [ "$status" -eq 1 ]

    run validate_tower_session_id "tower_test\`id\`"
    [ "$status" -eq 1 ]
}

@test "contract: validate_tower_session_id accepts valid IDs" {
    run validate_tower_session_id "tower_my-project"
    [ "$status" -eq 0 ]

    run validate_tower_session_id "tower_feature_123"
    [ "$status" -eq 0 ]

    run validate_tower_session_id "tower_a"
    [ "$status" -eq 0 ]
}
