#!/usr/bin/env bash
# navigator.sh - Session navigator using socket separation architecture
#
# Architecture:
#   default tmux server    = User's world (Claude Code sessions)
#   -L claude-tower server = Navigator's world (control center)
#
# The Navigator creates a dedicated tmux server (claude-tower) with:
#   - Left pane: Session list with vim-style navigation
#   - Right pane: Real-time view of selected session (connects to default server)
#
# Key bindings:
#   j/k    - Navigate sessions
#   Enter  - Full attach to selected session
#   i      - Input mode (focus on right pane)
#   Esc    - Return from input mode to list
#   n      - Create new session
#   d      - Delete session
#   R      - Restart Claude in session
#   q      - Quit Navigator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ============================================================================
# Configuration
# ============================================================================

# Cleanup on abnormal exit
trap 'cleanup_nav_state' EXIT INT TERM

# ============================================================================
# Helper Functions
# ============================================================================

# Get first tower session from default server
get_first_tower_session() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^tower_' | head -1 || echo ""
}

# Count tower sessions
count_tower_sessions() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -c '^tower_' || echo "0"
}

# ============================================================================
# Navigator Setup
# ============================================================================

# Create Navigator session in dedicated server
create_navigator() {
    debug_log "Creating Navigator session in -L $TOWER_NAV_SOCKET"

    # Ensure state directory exists
    ensure_nav_state_dir

    # Get first session to select
    local first_session
    first_session=$(get_first_tower_session)

    if [[ -n "$first_session" ]]; then
        set_nav_selected "$first_session"
    fi

    # Create new session in Navigator server
    # Unset TMUX to allow nested tmux
    TMUX= nav_tmux new-session -d -s "$TOWER_NAV_SESSION" -x "$(tput cols)" -y "$(tput lines)"

    # Split into left (list) and right (preview) panes
    nav_tmux split-window -t "$TOWER_NAV_SESSION" -h -l "70%"

    # Set up left pane (session list)
    nav_tmux send-keys -t "$TOWER_NAV_SESSION:0.0" \
        "$SCRIPT_DIR/navigator-list.sh" Enter

    # Set up right pane (preview wrapper)
    nav_tmux send-keys -t "$TOWER_NAV_SESSION:0.1" \
        "$SCRIPT_DIR/navigator-preview.sh" Enter

    # Focus on left pane
    nav_tmux select-pane -t "$TOWER_NAV_SESSION:0.0"

    debug_log "Navigator session created"
}

# Attach to Navigator
attach_navigator() {
    debug_log "Attaching to Navigator"

    # Need to unset TMUX to attach to different server
    TMUX= nav_tmux attach-session -t "$TOWER_NAV_SESSION"
}

# Kill Navigator and cleanup
kill_navigator() {
    debug_log "Killing Navigator"

    if is_nav_session_exists; then
        nav_tmux kill-session -t "$TOWER_NAV_SESSION" 2>/dev/null || true
    fi

    cleanup_nav_state
}

# ============================================================================
# Main Entry Points
# ============================================================================

# Open Navigator (main entry point)
open_navigator() {
    # Save caller session for return
    local current_session
    current_session=$(tmux display-message -p '#S' 2>/dev/null || echo "")

    if [[ -n "$current_session" && "$current_session" != "$TOWER_NAV_SESSION" ]]; then
        set_nav_caller "$current_session"
    fi

    # Check if Navigator already exists
    if is_nav_session_exists; then
        debug_log "Navigator already exists, attaching"
        attach_navigator
    else
        # Check if there are any sessions to navigate
        local session_count
        session_count=$(count_tower_sessions)

        if [[ "$session_count" -eq 0 ]]; then
            # No sessions - offer to create one
            handle_info "No tower sessions found. Use 'prefix + t n' to create a new session."
            return 0
        fi

        debug_log "Creating new Navigator"
        create_navigator
        attach_navigator
    fi
}

# Close Navigator and return to caller
close_navigator() {
    local caller
    caller=$(get_nav_caller)

    kill_navigator

    # Return to caller session if available
    if [[ -n "$caller" ]]; then
        if tmux has-session -t "$caller" 2>/dev/null; then
            tmux switch-client -t "$caller" 2>/dev/null || true
        fi
    fi
}

# Full attach to session (exit Navigator and attach directly)
full_attach() {
    local session_id="${1:-}"

    if [[ -z "$session_id" ]]; then
        session_id=$(get_nav_selected)
    fi

    if [[ -z "$session_id" ]]; then
        handle_error "No session selected"
        return 1
    fi

    # Validate session ID format (security)
    if ! validate_tower_session_id "$session_id"; then
        handle_error "Invalid session ID format"
        return 1
    fi

    # Check if session exists
    if ! tmux has-session -t "$session_id" 2>/dev/null; then
        # Try to restore if dormant
        local state
        state=$(get_session_state "$session_id")

        if [[ "$state" == "$STATE_DORMANT" ]]; then
            restore_session "$session_id"
        else
            handle_error "Session does not exist: ${session_id#tower_}"
            return 1
        fi
    fi

    # Kill Navigator
    kill_navigator

    # Attach to selected session in default server
    tmux switch-client -t "$session_id" 2>/dev/null || \
        tmux attach-session -t "$session_id" 2>/dev/null || true
}

# ============================================================================
# Usage
# ============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [command]

Commands:
    (default)       Open Navigator (or attach if already exists)
    --open          Open Navigator
    --close         Close Navigator and return to caller
    --attach <id>   Full attach to session, closing Navigator
    --kill          Kill Navigator server

Navigator Architecture:
    Uses socket separation with dedicated tmux server (-L $TOWER_NAV_SOCKET)
    Left pane shows session list, right pane shows live preview

Keybindings in Navigator:
    j/k, ↓/↑     Navigate sessions
    g/G          Go to first/last session
    Enter        Full attach to selected session
    i            Input mode (focus on preview pane)
    Esc          Return to list from input mode
    n            Create new session
    d            Delete selected session
    R            Restart Claude in session
    ?            Show help
    q            Quit Navigator

EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    case "${1:-}" in
        --open|"")
            open_navigator
            ;;
        --close)
            close_navigator
            ;;
        --attach)
            full_attach "${2:-}"
            ;;
        --kill)
            kill_nav_server
            ;;
        --help|-h)
            usage
            ;;
        *)
            handle_error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
}

main "$@"
