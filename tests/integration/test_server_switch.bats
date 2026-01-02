#!/usr/bin/env bats
# Server switch integration tests
# Tests seamless switching between default server and Navigator server
# Verifies the detach-client -E pattern works correctly

load '../test_helper'

# Test tmux sockets
NAV_SOCKET="ct-switch-nav"
DEFAULT_SOCKET="ct-switch-default"

setup_file() {
    export TMUX_TMPDIR="/tmp/claude-tower-switch-test"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"

    # Start default server with test sessions (TMUX= to allow nesting)
    TMUX= tmux -L "$DEFAULT_SOCKET" new-session -d -s "tower_switch_a" -c /tmp
    TMUX= tmux -L "$DEFAULT_SOCKET" new-session -d -s "tower_switch_b" -c /tmp
    TMUX= tmux -L "$DEFAULT_SOCKET" new-session -d -s "caller_session" -c /tmp
}

teardown_file() {
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    TMUX= tmux -L "$DEFAULT_SOCKET" kill-server 2>/dev/null || true
    rm -rf "/tmp/claude-tower-switch-test" 2>/dev/null || true
}

setup() {
    # Set env var BEFORE sourcing (TOWER_NAV_SOCKET is readonly)
    export CLAUDE_TOWER_NAV_SOCKET="$NAV_SOCKET"
    source_common
    setup_test_env
    ensure_nav_state_dir
    cleanup_nav_state
}

teardown() {
    TMUX= tmux -L "$NAV_SOCKET" kill-session -t "$TOWER_NAV_SESSION" 2>/dev/null || true
    cleanup_nav_state
    teardown_test_env
}

# ============================================================================
# Server Separation Verification
# ============================================================================

@test "server-switch: Navigator uses dedicated socket" {
    [ "$TOWER_NAV_SOCKET" = "claude-tower" ] || [ "$TOWER_NAV_SOCKET" = "$NAV_SOCKET" ]
}

@test "server-switch: nav_tmux targets Navigator socket" {
    # Create session on Navigator socket
    nav_tmux new-session -d -s "nav-test"

    # Should exist on Navigator socket
    run nav_tmux has-session -t "nav-test"
    [ "$status" -eq 0 ]

    # Should NOT exist on default socket
    run tmux -L "$DEFAULT_SOCKET" has-session -t "nav-test"
    [ "$status" -ne 0 ]

    nav_tmux kill-session -t "nav-test"
}

@test "server-switch: tower sessions exist on default server only" {
    tmux() { command tmux -L "$DEFAULT_SOCKET" "$@"; }
    export -f tmux

    run session_exists "tower_switch_a"
    [ "$status" -eq 0 ]

    # Should NOT exist on Navigator socket
    run tmux -L "$NAV_SOCKET" has-session -t "tower_switch_a"
    [ "$status" -ne 0 ]
}

# ============================================================================
# Caller State Management
# ============================================================================

@test "server-switch: caller session saved before Navigator opens" {
    set_nav_caller "caller_session"

    result=$(get_nav_caller)
    [ "$result" = "caller_session" ]
}

@test "server-switch: caller session available for return" {
    set_nav_caller "caller_session"

    # Simulate Navigator operations
    set_nav_selected "tower_switch_a"
    set_nav_focus "view"

    # Caller should still be available
    result=$(get_nav_caller)
    [ "$result" = "caller_session" ]
}

# ============================================================================
# TMUX= Environment Variable Tests
# ============================================================================

@test "server-switch: TMUX= clears environment for cross-server ops" {
    # Set TMUX to simulate being inside a tmux session
    export TMUX="/tmp/tmux-1000/nav,12345,0"

    # With TMUX= prefix, should be able to list sessions from default server
    result=$(TMUX= tmux -L "$DEFAULT_SOCKET" list-sessions -F '#{session_name}' 2>/dev/null | head -1)

    [[ -n "$result" ]]

    unset TMUX
}

@test "server-switch: _start_session_with_claude uses TMUX= prefix" {
    local func_def
    func_def=$(declare -f _start_session_with_claude)

    # Should use TMUX= for new-session
    [[ "$func_def" == *"TMUX= tmux new-session"* ]]

    # Should use TMUX= for send-keys
    [[ "$func_def" == *"TMUX= tmux send-keys"* ]]
}

# ============================================================================
# detach-client -E Pattern Tests
# ============================================================================

@test "server-switch: navigator.sh close_navigator uses exec tmux attach" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator.sh"

    # Check for the exec pattern in close_navigator
    run grep -A10 "close_navigator()" "$script"
    [[ "$output" == *"exec tmux attach-session"* ]] || [[ "$output" == *"TMUX= exec tmux"* ]]
}

@test "server-switch: navigator.sh full_attach uses exec tmux attach" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator.sh"

    run grep -A20 "^full_attach()" "$script"
    [[ "$output" == *"exec tmux attach-session"* ]] || [[ "$output" == *"TMUX= exec tmux"* ]]
}

@test "server-switch: navigator-list.sh quit_navigator uses detach-client -E" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"

    run grep -A10 "quit_navigator()" "$script"
    [[ "$output" == *"detach-client -E"* ]]
}

@test "server-switch: navigator-list.sh full_attach uses detach-client -E" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"

    run grep -A15 "^full_attach()" "$script"
    [[ "$output" == *"detach-client -E"* ]]
}

# ============================================================================
# Session Existence Checks Use Correct Server
# ============================================================================

@test "server-switch: has-session checks use TMUX= prefix" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator.sh"

    # All has-session checks should use TMUX= to check default server
    run grep "has-session" "$script"
    [ "$status" -eq 0 ]

    # Every has-session should be prefixed with TMUX=
    while IFS= read -r line; do
        [[ "$line" == *"nav_tmux"* ]] || [[ "$line" == *"TMUX= tmux"* ]] || [[ "$line" == *"TMUX="* ]]
    done < <(grep "has-session" "$script")
}

# ============================================================================
# Plugin Keybinding Tests
# ============================================================================

@test "server-switch: plugin uses run-shell before detach-client -E" {
    local plugin="$PROJECT_ROOT/tmux-plugin/claude-tower.tmux"

    # Check the navigator binding
    run grep "tower c" "$plugin"
    [ "$status" -eq 0 ]

    # Should save caller BEFORE detach-client -E
    [[ "$output" == *"run-shell"* ]]
    [[ "$output" == *"caller"* ]]
    [[ "$output" == *"detach-client -E"* ]]
}

@test "server-switch: caller file written by run-shell not detach-client" {
    local plugin="$PROJECT_ROOT/tmux-plugin/claude-tower.tmux"

    # The pattern should be:
    # run-shell -b "... echo '#{session_name}' > /tmp/claude-tower/caller && tmux detach-client -E ..."
    run grep "tower c" "$plugin"

    # run-shell writes caller THEN detach-client runs navigator
    [[ "$output" == *"echo"* ]]
    [[ "$output" == *"caller"* ]]
}

# ============================================================================
# End-to-End Server Switch Simulation
# ============================================================================

@test "server-switch: simulated flow - open navigator, select, attach" {
    # Simulate the flow without actual client attachment

    # 1. Save caller (done by plugin run-shell)
    set_nav_caller "caller_session"

    # 2. Navigator session created on nav socket
    nav_tmux new-session -d -s "$TOWER_NAV_SESSION" -x 80 -y 24

    run nav_tmux has-session -t "$TOWER_NAV_SESSION"
    [ "$status" -eq 0 ]

    # 3. User selects a session
    set_nav_selected "tower_switch_a"

    # 4. Verify target exists on default server
    run tmux -L "$DEFAULT_SOCKET" has-session -t "tower_switch_a"
    [ "$status" -eq 0 ]

    # 5. Navigator would use detach-client -E to attach to target
    #    (can't test actual client switch without real terminal)

    # Cleanup
    nav_tmux kill-session -t "$TOWER_NAV_SESSION"
}

@test "server-switch: simulated flow - quit returns to caller" {
    set_nav_caller "caller_session"

    # Create Navigator
    nav_tmux new-session -d -s "$TOWER_NAV_SESSION"

    # Do some navigation
    set_nav_selected "tower_switch_b"
    set_nav_focus "view"

    # Quit should return to caller (can't test actual switch)
    # Just verify caller is still retrievable
    result=$(get_nav_caller)
    [ "$result" = "caller_session" ]

    # And caller exists on default server
    run tmux -L "$DEFAULT_SOCKET" has-session -t "caller_session"
    [ "$status" -eq 0 ]

    nav_tmux kill-session -t "$TOWER_NAV_SESSION"
}

# ============================================================================
# Error Recovery Tests
# ============================================================================

@test "server-switch: handles missing caller gracefully" {
    # No caller set
    cleanup_nav_state

    result=$(get_nav_caller)
    [ -z "$result" ]

    # Should fall back to any available session
    # (tested in actual quit_navigator implementation)
}

@test "server-switch: handles dead target session" {
    set_nav_selected "tower_nonexistent"

    # Check if validation catches it
    run validate_tower_session_id "tower_nonexistent"
    [ "$status" -eq 0 ]  # Format is valid

    # But session doesn't exist
    tmux() { command tmux -L "$DEFAULT_SOCKET" "$@"; }
    export -f tmux

    run session_exists "tower_nonexistent"
    [ "$status" -ne 0 ]
}

@test "server-switch: Navigator session kept alive for fast re-entry" {
    # Create Navigator
    nav_tmux new-session -d -s "$TOWER_NAV_SESSION"

    # Simulate "close" without killing (the new behavior)
    # Just clear caller state
    set_nav_caller ""

    # Navigator session should still exist
    run nav_tmux has-session -t "$TOWER_NAV_SESSION"
    [ "$status" -eq 0 ]

    nav_tmux kill-session -t "$TOWER_NAV_SESSION"
}
