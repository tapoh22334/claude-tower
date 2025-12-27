#!/usr/bin/env bats
# Unit tests for navigator.sh functions and socket separation architecture

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

# ============================================================================
# Navigator state management tests (socket separation)
# ============================================================================

@test "TOWER_NAV_SOCKET: is set to claude-tower" {
    [ "$TOWER_NAV_SOCKET" = "claude-tower" ]
}

@test "TOWER_NAV_SESSION: is set to navigator" {
    [ "$TOWER_NAV_SESSION" = "navigator" ]
}

@test "TOWER_NAV_STATE_DIR: is in /tmp" {
    [[ "$TOWER_NAV_STATE_DIR" == /tmp/* ]]
}

@test "ensure_nav_state_dir: creates state directory" {
    rm -rf "$TOWER_NAV_STATE_DIR" 2>/dev/null || true

    run ensure_nav_state_dir

    [ "$status" -eq 0 ]
    [ -d "$TOWER_NAV_STATE_DIR" ]

    rm -rf "$TOWER_NAV_STATE_DIR" 2>/dev/null || true
}

@test "set_nav_selected and get_nav_selected: round trip works" {
    ensure_nav_state_dir

    set_nav_selected "tower_test-session"
    run get_nav_selected

    [ "$status" -eq 0 ]
    [ "$output" = "tower_test-session" ]

    cleanup_nav_state
}

@test "set_nav_caller and get_nav_caller: round trip works" {
    ensure_nav_state_dir

    set_nav_caller "my-session"
    run get_nav_caller

    [ "$status" -eq 0 ]
    [ "$output" = "my-session" ]

    cleanup_nav_state
}

@test "set_nav_focus and get_nav_focus: round trip works" {
    ensure_nav_state_dir

    set_nav_focus "preview"
    run get_nav_focus

    [ "$status" -eq 0 ]
    [ "$output" = "preview" ]

    cleanup_nav_state
}

@test "get_nav_focus: returns 'list' as default" {
    ensure_nav_state_dir
    rm -f "$TOWER_NAV_FOCUS_FILE" 2>/dev/null || true

    run get_nav_focus

    [ "$status" -eq 0 ]
    [ "$output" = "list" ]

    cleanup_nav_state
}

@test "cleanup_nav_state: removes all state files" {
    ensure_nav_state_dir
    set_nav_selected "tower_test"
    set_nav_caller "my-session"
    set_nav_focus "preview"

    run cleanup_nav_state

    [ "$status" -eq 0 ]
    [ ! -f "$TOWER_NAV_SELECTED_FILE" ]
    [ ! -f "$TOWER_NAV_CALLER_FILE" ]
    [ ! -f "$TOWER_NAV_FOCUS_FILE" ]
}

@test "nav_tmux: wrapper function exists" {
    # This test just verifies the function exists and can be called
    # Actual socket functionality requires a running tmux
    run type nav_tmux

    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

# ============================================================================
# Navigator script file tests
# ============================================================================

@test "navigator.sh: exists and is executable" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator.sh"
    [ -f "$script" ]
    [ -x "$script" ]
}

@test "navigator-list.sh: exists and is executable" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
    [ -f "$script" ]
    [ -x "$script" ]
}

@test "navigator-preview.sh: exists and is executable" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator-preview.sh"
    [ -f "$script" ]
    [ -x "$script" ]
}

@test "inner-tmux.conf: exists" {
    local conf="$PROJECT_ROOT/tmux-plugin/conf/inner-tmux.conf"
    [ -f "$conf" ]
}

@test "navigator.sh: --help shows usage" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator.sh"

    # Need to suppress sourcing common.sh's side effects
    run bash -c "set +euo pipefail; source '$PROJECT_ROOT/tmux-plugin/lib/common.sh'; $script --help 2>/dev/null || true"

    [[ "$output" == *"Usage"* ]] || [[ "$output" == *"navigator"* ]]
}

# ============================================================================
# Architecture validation tests
# ============================================================================

@test "claude-tower.tmux: Navigator uses run-shell not display-popup" {
    local plugin="$PROJECT_ROOT/tmux-plugin/claude-tower.tmux"

    run grep "tower c" "$plugin"

    [ "$status" -eq 0 ]
    [[ "$output" == *"run-shell"* ]]
    [[ "$output" != *"display-popup"* ]]
}

@test "inner-tmux.conf: disables prefix key" {
    local conf="$PROJECT_ROOT/tmux-plugin/conf/inner-tmux.conf"

    run grep "prefix None" "$conf"

    [ "$status" -eq 0 ]
}

@test "inner-tmux.conf: binds Escape to detach" {
    local conf="$PROJECT_ROOT/tmux-plugin/conf/inner-tmux.conf"

    run grep "Escape detach" "$conf"

    [ "$status" -eq 0 ]
}

@test "inner-tmux.conf: disables status bar" {
    local conf="$PROJECT_ROOT/tmux-plugin/conf/inner-tmux.conf"

    run grep "status off" "$conf"

    [ "$status" -eq 0 ]
}
