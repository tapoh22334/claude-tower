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
    # Set env vars BEFORE sourcing (sockets are readonly)
    export CLAUDE_TOWER_NAV_SOCKET="$NAV_SOCKET"
    export CLAUDE_TOWER_SESSION_SOCKET="$DEFAULT_SOCKET"
    export TMUX_TMPDIR="/tmp/claude-tower-display-test"
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

## Skipped: session list header test requires running navigator-list.sh
## Use scenario tests instead

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

    run get_state_icon "dormant"
    [ "$output" = "○" ]

    # Unknown states return ?
    run get_state_icon "unknown"
    [ "$output" = "?" ]
}

@test "display: type icons removed in v2 (directory-based sessions)" {
    # v2 uses directory-based sessions only, no type icons needed
    # Verify get_state_icon still works for v2 states
    run get_state_icon "active"
    [ "$output" = "▶" ]
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

@test "display: color constants use escape notation" {
    # Colors use \033 notation (interpreted by echo -e)
    [[ "$C_RED" == *"\\033["* ]]
    [[ "$C_GREEN" == *"\\033["* ]]
    [[ "$C_RESET" == *"\\033["* ]]
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
