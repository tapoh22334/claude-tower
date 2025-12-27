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
# Invocation modes:
#   --direct    Called from detach-client -E (seamless server switching)
#   --open      Open Navigator (legacy popup mode)
#   --close     Close Navigator and return to caller
#   --attach    Full attach to session
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

# Don't trap EXIT in direct mode - let the shell handle it
# trap 'cleanup_nav_state' EXIT INT TERM

# ============================================================================
# Helper Functions
# ============================================================================

# Get first tower session from default server
get_first_tower_session() {
    TMUX= tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^tower_' | head -1 || echo ""
}

# Count tower sessions on default server
count_tower_sessions() {
    TMUX= tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -c '^tower_' || echo "0"
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
    info_log "Attaching to Navigator"

    # Check if we have a terminal (required for attach)
    if ! tty -s 2>/dev/null; then
        local err_msg="Cannot attach: no terminal available. Use 'prefix + t, c' from tmux, or run directly in terminal."
        error_log "$err_msg"
        tmux display-message "❌ $err_msg" 2>/dev/null || true
        tmux display-message "📋 Log: $TOWER_LOG_FILE" 2>/dev/null || true
        return 1
    fi

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
    info_log "Opening Navigator..."

    # Early check: do we have a terminal?
    if ! tty -s 2>/dev/null; then
        local err_msg="Navigator requires a terminal. Cannot run in background mode."
        error_log "$err_msg"
        tmux display-message "❌ $err_msg" 2>/dev/null || true
        tmux display-message "💡 Try: tmux display-popup -E -w 90% -h 90% '$SCRIPT_DIR/navigator.sh'" 2>/dev/null || true
        return 1
    fi

    # Save caller session for return
    local current_session
    current_session=$(tmux display-message -p '#S' 2>/dev/null || echo "")

    if [[ -n "$current_session" && "$current_session" != "$TOWER_NAV_SESSION" ]]; then
        set_nav_caller "$current_session"
    fi

    # Check if Navigator already exists
    if is_nav_session_exists; then
        info_log "Navigator already exists, attaching"
        attach_navigator
    else
        # Check if there are any sessions to navigate
        local session_count
        session_count=$(count_tower_sessions)

        if [[ "$session_count" -eq 0 ]]; then
            # No sessions - offer to create one
            handle_info "No tower sessions found. Use 'prefix + t n' to create a new session."
            info_log "No tower sessions found"
            return 0
        fi

        info_log "Creating new Navigator (session count: $session_count)"
        create_navigator
        attach_navigator
    fi
}

# Close Navigator and return to caller (detach-client -E version)
# This is called from within Navigator to exit and return to default server
# NOTE: Navigator session is kept alive for fast re-entry
close_navigator() {
    local caller
    caller=$(get_nav_caller)

    info_log "Closing Navigator (keeping session alive), returning to caller: ${caller:-<none>}"

    # Determine target session on default server
    local target_session=""
    if [[ -n "$caller" ]] && TMUX= tmux has-session -t "$caller" 2>/dev/null; then
        target_session="$caller"
    else
        # Fallback: find any session on default server
        target_session=$(TMUX= tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")
    fi

    # DON'T kill Navigator session - keep it for fast re-entry
    # Just clear the caller state (will be set again on next entry)
    # cleanup_nav_state  # Don't clear - keep selected state too

    # Use exec to seamlessly return to default server
    if [[ -n "$target_session" ]]; then
        info_log "Detaching and attaching to: $target_session"
        exec tmux attach-session -t "$target_session"
    else
        info_log "No target session, just exiting"
        exit 0
    fi
}

# Close Navigator (legacy version for popup mode)
close_navigator_legacy() {
    local caller
    caller=$(get_nav_caller)

    kill_navigator

    # Return to caller session if available (on default server)
    if [[ -n "$caller" ]]; then
        if TMUX= tmux has-session -t "$caller" 2>/dev/null; then
            TMUX= tmux switch-client -t "$caller" 2>/dev/null || true
        fi
    fi
}

# Full attach to session (exit Navigator and attach directly)
# Uses exec to seamlessly switch to the target session
# NOTE: Navigator session is kept alive for fast re-entry
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

    # Check if session exists on default server
    if ! TMUX= tmux has-session -t "$session_id" 2>/dev/null; then
        # Try to restore if dormant
        local state
        state=$(get_session_state "$session_id")

        if [[ "$state" == "$STATE_DORMANT" ]]; then
            info_log "Restoring dormant session: $session_id"
            restore_session "$session_id"
        else
            handle_error "Session does not exist: ${session_id#tower_}"
            return 1
        fi
    fi

    info_log "Full attach to session: $session_id"

    # DON'T kill Navigator session - keep it for fast re-entry
    # The session list and preview will continue running in background

    # Use exec to seamlessly attach to the target session
    exec tmux attach-session -t "$session_id"
}

# ============================================================================
# Direct Mode (for detach-client -E)
# ============================================================================

# Direct mode entry point - called from detach-client -E
# This runs AFTER detaching from default server, directly in the user's terminal
# Arguments:
#   --caller <session>  The session to return to when exiting Navigator
open_navigator_direct() {
    local caller_session=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --caller)
                caller_session="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    info_log "Opening Navigator (direct mode), caller: ${caller_session:-<none>}"

    # Save caller session for return
    if [[ -n "$caller_session" ]]; then
        set_nav_caller "$caller_session"
    fi

    # Check if Navigator session already exists
    if is_nav_session_exists; then
        info_log "Navigator exists, attaching directly"
        # Just attach - very fast!
        # Note: Can't use nav_tmux function with exec, must use direct command
        exec tmux -L "$TOWER_NAV_SOCKET" attach-session -t "$TOWER_NAV_SESSION"
    fi

    # Check if there are any sessions to navigate
    local session_count
    session_count=$(count_tower_sessions)

    if [[ "$session_count" -eq 0 ]]; then
        echo "No tower sessions found. Use 'prefix + t n' to create a new session."
        info_log "No tower sessions found"
        # Return to default server
        local any_session
        any_session=$(TMUX= tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")
        if [[ -n "$any_session" ]]; then
            exec tmux attach-session -t "$any_session"
        fi
        exit 0
    fi

    info_log "Creating new Navigator (session count: $session_count)"

    # Ensure state directory exists
    ensure_nav_state_dir

    # Get first session to select
    local first_session
    first_session=$(get_first_tower_session)
    if [[ -n "$first_session" ]]; then
        set_nav_selected "$first_session"
    fi

    # Create Navigator session
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

    info_log "Navigator session created, attaching"

    # Attach to Navigator (this replaces the current process)
    # Note: Can't use nav_tmux function with exec, must use direct command
    exec tmux -L "$TOWER_NAV_SOCKET" attach-session -t "$TOWER_NAV_SESSION"
}

# ============================================================================
# Usage
# ============================================================================

usage() {
    cat <<EOF
Usage: $(basename "$0") [command]

Commands:
    (default)       Open Navigator (popup mode, legacy)
    --direct        Open Navigator (direct mode, for detach-client -E)
    --open          Open Navigator (popup mode)
    --close         Close Navigator and return to caller
    --attach <id>   Full attach to session
    --kill          Kill Navigator server

Navigator Architecture:
    Uses socket separation with dedicated tmux server (-L $TOWER_NAV_SOCKET)
    Left pane shows session list, right pane shows live preview

Invocation:
    From tmux:     prefix + t, c  (uses detach-client -E for seamless switching)
    Direct:        ./navigator.sh --direct

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
        --direct)
            # New seamless mode via detach-client -E
            shift
            open_navigator_direct "$@"
            ;;
        --open|"")
            # Legacy popup mode
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
