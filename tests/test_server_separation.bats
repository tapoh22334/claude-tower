#!/usr/bin/env bats
# Unit tests for server separation ensuring tower sessions
# are created/accessed on the dedicated session server (-L claude-tower-sessions)
# not the Navigator server or user's default server

load 'test_helper'

setup() {
    source_common
}

# ============================================================================
# get_active_sessions tests
# ============================================================================

@test "get_active_sessions: function exists" {
    run type get_active_sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "get_active_sessions: uses session_tmux helper" {
    local func_def
    func_def=$(declare -f get_active_sessions)

    [[ "$func_def" == *"session_tmux"* ]]
}

# ============================================================================
# session_exists tests
# ============================================================================

@test "session_exists: function exists" {
    run type session_exists
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "session_exists: uses session_tmux helper" {
    local func_def
    func_def=$(declare -f session_exists)

    [[ "$func_def" == *"session_tmux"* ]]
}

# ============================================================================
# get_session_state tests
# ============================================================================

@test "get_session_state: function exists" {
    run type get_session_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "get_session_state: uses session_tmux for has-session" {
    local func_def
    func_def=$(declare -f get_session_state)

    # The function uses session_tmux has-session for reliable existence check
    [[ "$func_def" == *"session_tmux has-session"* ]]
}

# Note: get_session_state no longer uses capture-pane or display-message

# ============================================================================
# _start_session_with_claude tests
# ============================================================================

@test "_start_session_with_claude: function exists" {
    run type _start_session_with_claude
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "_start_session_with_claude: uses session_tmux for new-session" {
    local func_def
    func_def=$(declare -f _start_session_with_claude)

    [[ "$func_def" == *"session_tmux new-session"* ]]
}

@test "_start_session_with_claude: uses session_tmux for send-keys" {
    local func_def
    func_def=$(declare -f _start_session_with_claude)

    [[ "$func_def" == *"session_tmux send-keys"* ]]
}

# ============================================================================
# delete_session tests
# ============================================================================

@test "delete_session: function exists" {
    run type delete_session
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "delete_session: uses session_tmux for kill-session" {
    local func_def
    func_def=$(declare -f delete_session)

    [[ "$func_def" == *"session_tmux kill-session"* ]]
}

# ============================================================================
# restart_session tests
# ============================================================================

@test "restart_session: function exists" {
    run type restart_session
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "restart_session: uses session_tmux for send-keys" {
    local func_def
    func_def=$(declare -f restart_session)

    [[ "$func_def" == *"session_tmux send-keys"* ]]
}

# ============================================================================
# send_to_session tests
# ============================================================================

@test "send_to_session: function exists" {
    run type send_to_session
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "send_to_session: uses session_tmux for send-keys" {
    local func_def
    func_def=$(declare -f send_to_session)

    [[ "$func_def" == *"session_tmux send-keys"* ]]
}

# ============================================================================
# list_all_sessions tests
# ============================================================================

@test "list_all_sessions: function exists" {
    run type list_all_sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "list_all_sessions: uses session_tmux for list-sessions" {
    local func_def
    func_def=$(declare -f list_all_sessions)

    [[ "$func_def" == *"session_tmux list-sessions"* ]]
}

# ============================================================================
# Navigator script tests
# ============================================================================

@test "navigator.sh: get_first_tower_session uses session_tmux" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator.sh"

    run grep "get_first_tower_session" "$script"
    [ "$status" -eq 0 ]

    run grep "session_tmux list-sessions" "$script"
    [ "$status" -eq 0 ]
}

@test "navigator.sh: count_tower_sessions uses session_tmux" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator.sh"

    run grep "count_tower_sessions" "$script"
    [ "$status" -eq 0 ]

    # Verify the function uses session_tmux
    run grep -A2 "^count_tower_sessions()" "$script"
    [[ "$output" == *"session_tmux"* ]]
}

@test "navigator.sh: full_attach uses session server attach" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator.sh"

    # Check for session server attach pattern
    run grep "TOWER_SESSION_SOCKET" "$script"
    [ "$status" -eq 0 ]
}

@test "navigator-list.sh: build_session_list uses session_tmux" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"

    # The script uses session_tmux list-sessions in build_session_list
    run grep "session_tmux list-sessions" "$script"
    [ "$status" -eq 0 ]
}

@test "session-new.sh: uses session_tmux for switch-client" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/session-new.sh"

    run grep "session_tmux switch-client" "$script"
    [ "$status" -eq 0 ]
}

@test "session_tmux: helper function exists and uses session socket" {
    run type session_tmux
    [ "$status" -eq 0 ]

    local func_def
    func_def=$(declare -f session_tmux)

    # Should use TOWER_SESSION_SOCKET
    [[ "$func_def" == *"TOWER_SESSION_SOCKET"* ]]
}
