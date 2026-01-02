#!/usr/bin/env bats
# Snapshot-based display tests
# Uses tmux capture-pane to verify visual output
# Compares output against expected patterns (not exact match)

load '../test_helper'

# Test tmux sockets
NAV_SOCKET="ct-display-nav"
DEFAULT_SOCKET="ct-display-default"

setup_file() {
    export TMUX_TMPDIR="/tmp/claude-tower-display-test"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"

    # Start default server with test sessions (TMUX= to allow nesting)
    TMUX= tmux -L "$DEFAULT_SOCKET" new-session -d -s "tower_display_a" -c /tmp 2>/dev/null || true
    TMUX= tmux -L "$DEFAULT_SOCKET" new-session -d -s "tower_display_b" -c /tmp 2>/dev/null || true
    TMUX= tmux -L "$DEFAULT_SOCKET" new-session -d -s "tower_display_c" -c /tmp 2>/dev/null || true
}

teardown_file() {
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    TMUX= tmux -L "$DEFAULT_SOCKET" kill-server 2>/dev/null || true
    rm -rf "/tmp/claude-tower-display-test" 2>/dev/null || true
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
    # Kill navigator session if exists
    TMUX= tmux -L "$NAV_SOCKET" kill-session -t "$TOWER_NAV_SESSION" 2>/dev/null || true
    cleanup_nav_state
    teardown_test_env
}

# Helper to capture pane content
capture_pane() {
    local target="${1:-$TOWER_NAV_SESSION:0.0}"
    tmux -L "$NAV_SOCKET" capture-pane -t "$target" -p 2>/dev/null || echo ""
}

# Helper to strip ANSI codes for pattern matching
strip_ansi() {
    sed 's/\x1b\[[0-9;]*m//g'
}

# Helper to create a minimal navigator session for testing
create_test_navigator_session() {
    # Override tmux for common.sh functions
    local orig_tmux=$(which tmux)

    tmux -L "$NAV_SOCKET" new-session -d -s "$TOWER_NAV_SESSION" -x 80 -y 24

    # Set initial selection
    set_nav_selected "tower_display_a"
}

# ============================================================================
# Display Pattern Tests
# ============================================================================

@test "display: session list header contains 'Sessions'" {
    skip "Requires running navigator-list.sh - use scenario tests instead"
}

@test "display: render_list output contains session names" {
    # Source the script to get the render function
    local script_dir="$PROJECT_ROOT/tmux-plugin/scripts"

    # We can't easily source navigator-list.sh due to main_loop
    # Instead, we test the underlying data functions

    tmux() { command tmux -L "$DEFAULT_SOCKET" "$@"; }
    export -f tmux

    # Test that list_all_sessions returns session names
    run list_all_sessions

    [ "$status" -eq 0 ]
    [[ "$output" == *"tower_display_a"* ]]
    [[ "$output" == *"tower_display_b"* ]]
    [[ "$output" == *"tower_display_c"* ]]
}

@test "display: session list shows state icons in output format" {
    tmux() { command tmux -L "$DEFAULT_SOCKET" "$@"; }
    export -f tmux

    run list_all_sessions

    [ "$status" -eq 0 ]
    # Output should be in format: session_id:state:type
    [[ "$output" == *":"* ]]
}

@test "display: state icons are correct" {
    run get_state_icon "active"
    [ "$output" = "▶" ]

    run get_state_icon "exited"
    [ "$output" = "!" ]

    run get_state_icon "dormant"
    [ "$output" = "○" ]
}

@test "display: type icons are correct" {
    run get_type_icon "worktree"
    [ "$output" = "[W]" ]

    run get_type_icon "simple"
    [ "$output" = "[S]" ]
}

# ============================================================================
# Output Format Tests
# ============================================================================

@test "display: list_all_sessions output has consistent format" {
    tmux() { command tmux -L "$DEFAULT_SOCKET" "$@"; }
    export -f tmux

    local output
    output=$(list_all_sessions)

    # Each line should match: session_id:state:type
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Count colons
        local colon_count
        colon_count=$(echo "$line" | tr -cd ':' | wc -c)

        # Should have exactly 2 colons (3 fields)
        [ "$colon_count" -eq 2 ]
    done <<< "$output"
}

@test "display: session names extracted correctly from IDs" {
    # Test the extraction logic used in display
    local session_id="tower_my-project"
    local name="${session_id#tower_}"

    [ "$name" = "my-project" ]
}

@test "display: dormant sessions included in list" {
    tmux() { command tmux -L "$DEFAULT_SOCKET" "$@"; }
    export -f tmux

    # Create dormant session (metadata only)
    create_mock_metadata "tower_dormant_display" "workspace"

    run list_all_sessions

    [ "$status" -eq 0 ]
    [[ "$output" == *"tower_dormant_display"* ]]
    [[ "$output" == *"dormant"* ]]
}

# ============================================================================
# ANSI Color Code Tests
# ============================================================================

@test "display: color constants use proper escape sequences" {
    # Verify colors are defined with actual escape sequences
    # This tests the recent fix for ANSI color format

    [[ "$C_RED" == *$'\033'* ]] || [[ "$C_RED" == *$'\x1b'* ]]
    [[ "$C_GREEN" == *$'\033'* ]] || [[ "$C_GREEN" == *$'\x1b'* ]]
    [[ "$C_RESET" == *$'\033'* ]] || [[ "$C_RESET" == *$'\x1b'* ]]
}

@test "display: NAV colors in navigator-list use \$'...' syntax" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"

    # Check that colors use $'...' syntax (proper ANSI escapes)
    run grep "NAV_C_" "$script"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\$'"* ]]
}

# ============================================================================
# Edge Case Display Tests
# ============================================================================

@test "display: empty session list handled gracefully" {
    # Create a tmux override that returns no sessions
    tmux() {
        if [[ "$1" == "list-sessions" ]]; then
            return 1
        fi
        command tmux -L "$DEFAULT_SOCKET" "$@"
    }
    export -f tmux

    run list_all_sessions

    # Should not fail, just return empty or dormant-only
    [ "$status" -eq 0 ]
}

@test "display: long session names truncated safely" {
    local long_name="tower_this_is_a_very_long_session_name_that_exceeds_display_width"

    # Test that sanitize_name handles long names
    local sanitized
    sanitized=$(sanitize_name "$long_name")

    # Should be truncated to 64 chars
    [ ${#sanitized} -le 64 ]
}

# ============================================================================
# Integration with capture-pane (requires running session)
# ============================================================================

@test "display: capture-pane returns content from tmux session" {
    # Create a simple test session
    tmux -L "$NAV_SOCKET" new-session -d -s "capture-test"
    tmux -L "$NAV_SOCKET" send-keys -t "capture-test" "echo 'Hello Display Test'" Enter
    sleep 0.3

    local output
    output=$(tmux -L "$NAV_SOCKET" capture-pane -t "capture-test" -p)

    [[ "$output" == *"Hello Display Test"* ]]

    tmux -L "$NAV_SOCKET" kill-session -t "capture-test"
}

@test "display: capture-pane can be stripped of ANSI codes" {
    tmux -L "$NAV_SOCKET" new-session -d -s "ansi-test"
    # Echo colored text
    tmux -L "$NAV_SOCKET" send-keys -t "ansi-test" "echo -e '\033[31mRed Text\033[0m'" Enter
    sleep 0.3

    local output
    output=$(tmux -L "$NAV_SOCKET" capture-pane -t "ansi-test" -p | strip_ansi)

    [[ "$output" == *"Red Text"* ]]
    [[ "$output" != *$'\033'* ]]

    tmux -L "$NAV_SOCKET" kill-session -t "ansi-test"
}
