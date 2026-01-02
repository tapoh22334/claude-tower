#!/usr/bin/env bats
# Unit tests for server separation (TMUX= prefix) ensuring tower sessions
# are always created/accessed on the default server, not Navigator server

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

@test "get_active_sessions: uses TMUX= prefix" {
    local func_def
    func_def=$(declare -f get_active_sessions)

    [[ "$func_def" == *"TMUX= tmux"* ]]
}

# ============================================================================
# session_exists tests
# ============================================================================

@test "session_exists: function exists" {
    run type session_exists
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "session_exists: uses TMUX= prefix" {
    local func_def
    func_def=$(declare -f session_exists)

    [[ "$func_def" == *"TMUX= tmux"* ]]
}

# ============================================================================
# get_session_state tests
# ============================================================================

@test "get_session_state: function exists" {
    run type get_session_state
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "get_session_state: uses TMUX= prefix for has-session" {
    local func_def
    func_def=$(declare -f get_session_state)

    [[ "$func_def" == *"TMUX= tmux has-session"* ]]
}

@test "get_session_state: uses TMUX= prefix for display-message" {
    local func_def
    func_def=$(declare -f get_session_state)

    [[ "$func_def" == *"TMUX= tmux display-message"* ]]
}

# Note: get_session_state no longer uses capture-pane (uses display-message instead)

# ============================================================================
# _start_session_with_claude tests
# ============================================================================

@test "_start_session_with_claude: function exists" {
    run type _start_session_with_claude
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "_start_session_with_claude: uses TMUX= prefix for new-session" {
    local func_def
    func_def=$(declare -f _start_session_with_claude)

    [[ "$func_def" == *"TMUX= tmux new-session"* ]]
}

@test "_start_session_with_claude: uses TMUX= prefix for send-keys" {
    local func_def
    func_def=$(declare -f _start_session_with_claude)

    [[ "$func_def" == *"TMUX= tmux send-keys"* ]]
}

# ============================================================================
# delete_session tests
# ============================================================================

@test "delete_session: function exists" {
    run type delete_session
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "delete_session: uses TMUX= prefix for kill-session" {
    local func_def
    func_def=$(declare -f delete_session)

    [[ "$func_def" == *"TMUX= tmux kill-session"* ]]
}

# ============================================================================
# restart_session tests
# ============================================================================

@test "restart_session: function exists" {
    run type restart_session
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "restart_session: uses TMUX= prefix for send-keys" {
    local func_def
    func_def=$(declare -f restart_session)

    [[ "$func_def" == *"TMUX= tmux send-keys"* ]]
}

# ============================================================================
# send_to_session tests
# ============================================================================

@test "send_to_session: function exists" {
    run type send_to_session
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "send_to_session: uses TMUX= prefix for send-keys" {
    local func_def
    func_def=$(declare -f send_to_session)

    [[ "$func_def" == *"TMUX= tmux send-keys"* ]]
}

# ============================================================================
# list_all_sessions tests
# ============================================================================

@test "list_all_sessions: function exists" {
    run type list_all_sessions
    [ "$status" -eq 0 ]
    [[ "$output" == *"function"* ]]
}

@test "list_all_sessions: uses TMUX= prefix for list-sessions" {
    local func_def
    func_def=$(declare -f list_all_sessions)

    [[ "$func_def" == *"TMUX= tmux list-sessions"* ]]
}

# ============================================================================
# Navigator script tests
# ============================================================================

@test "navigator.sh: get_first_tower_session uses TMUX= prefix" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator.sh"

    run grep "get_first_tower_session" "$script"
    [ "$status" -eq 0 ]

    run grep "TMUX= tmux list-sessions" "$script"
    [ "$status" -eq 0 ]
}

@test "navigator.sh: count_tower_sessions uses TMUX= prefix" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator.sh"

    run grep "count_tower_sessions" "$script"
    [ "$status" -eq 0 ]

    # Verify the function uses TMUX= prefix
    run grep -A2 "^count_tower_sessions()" "$script"
    [[ "$output" == *"TMUX= tmux"* ]]
}

@test "navigator.sh: full_attach uses TMUX= prefix" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator.sh"

    run grep "TMUX= tmux switch-client" "$script"
    [ "$status" -eq 0 ]

    # Check for TMUX= prefix with attach-session (may use 'exec tmux' or 'nav_tmux')
    run grep -E "TMUX=.*(tmux|nav_tmux) attach-session" "$script"
    [ "$status" -eq 0 ]
}

@test "navigator-list.sh: build_session_list uses TMUX= prefix" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"

    run grep "TMUX= tmux list-sessions" "$script"
    [ "$status" -eq 0 ]
}

@test "navigator-list.sh: restart_selected uses TMUX= prefix" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"

    run grep "TMUX= tmux send-keys" "$script"
    [ "$status" -eq 0 ]
}

@test "session-new.sh: uses TMUX= prefix for switch-client" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/session-new.sh"

    run grep "TMUX= tmux switch-client" "$script"
    [ "$status" -eq 0 ]
}

@test "session-new.sh: uses TMUX= prefix for display-message" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/session-new.sh"

    run grep "TMUX= tmux display-message" "$script"
    [ "$status" -eq 0 ]
}
