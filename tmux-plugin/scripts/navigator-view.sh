#!/usr/bin/env bash
# navigator-view.sh - Right pane: Real-time view of selected session
#
# This script runs in the right pane of Navigator.
# It connects to the selected session in the default tmux server using a nested tmux.
# When Escape is pressed, the inner tmux detaches and this script re-attaches to the
# (possibly new) selected session.
#
# The key insight: This creates a "tmux in tmux" setup where:
#   - Outer tmux: Navigator server (-L claude-tower)
#   - Inner tmux: Connection to default server's session

# Use pipefail but handle errors gracefully instead of exiting
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Error handler - log and continue instead of exiting
handle_script_error() {
    local line="$1"
    error_log "navigator-view.sh: Error at line $line"
    # Don't exit - the main loop will continue
}

# ============================================================================
# Configuration
# ============================================================================

# Ensure absolute path for view-focus.conf (important for nested tmux)
CONF_DIR="$(cd "$SCRIPT_DIR/../conf" 2>/dev/null && pwd)"
readonly CONF_DIR
readonly INNER_CONF="$CONF_DIR/view-focus.conf"

# Log script startup
info_log "Navigator view pane started (PID: $$)"
info_log "SCRIPT_DIR: $SCRIPT_DIR"
info_log "CONF_DIR: $CONF_DIR"
info_log "INNER_CONF path: $INNER_CONF"
info_log "INNER_CONF exists: $([[ -f "$INNER_CONF" ]] && echo yes || echo no)"
info_log "Current TMUX: ${TMUX:-<unset>}"

# ============================================================================
# Preview Functions
# ============================================================================

# Show placeholder when no session is selected
show_placeholder() {
    clear
    echo ""
    echo "  ┌───────────────────────────────────────┐"
    echo "  │                                       │"
    echo "  │   Select a session to view            │"
    echo "  │                                       │"
    echo "  │   Use j/k to navigate                 │"
    echo "  │   Press Enter to attach               │"
    echo "  │                                       │"
    echo "  └───────────────────────────────────────┘"
    echo ""
}

# Show error message
show_error() {
    local msg="$1"
    clear
    echo ""
    echo "  ┌───────────────────────────────────────┐"
    echo "  │  ⚠️  Preview Error                     │"
    echo "  │                                       │"
    printf "  │  %-37s │\n" "${msg:0:37}"
    echo "  │                                       │"
    echo "  │  Check log: ~/.claude-tower/metadata/ │"
    echo "  │  tower.log                            │"
    echo "  │                                       │"
    echo "  └───────────────────────────────────────┘"
    echo ""
}

# Show connecting message
show_connecting() {
    local session_id="$1"
    local name="${session_id#tower_}"

    # Get focus state for indicator
    local focus
    focus=$(get_nav_focus)
    local focus_header=""
    if [[ "$focus" == "view" ]]; then
        focus_header="  [INPUT MODE] Press Escape to return\n\n"
    fi

    clear
    echo ""
    printf "%b" "$focus_header"
    echo "  ┌───────────────────────────────────────┐"
    echo "  │                                       │"
    printf "  │  Connecting to: %-20s │\n" "${name:0:20}"
    echo "  │                                       │"
    echo "  │  Press Escape to return to list       │"
    echo "  │                                       │"
    echo "  └───────────────────────────────────────┘"
    echo ""
}

# Show dormant session info
show_dormant_info() {
    local session_id="$1"
    local name="${session_id#tower_}"

    clear
    echo ""
    echo "  ┌───────────────────────────────────────┐"
    echo "  │                                       │"
    echo "  │   Session: $name"
    echo "  │   Status: Dormant (not running)       │"
    echo "  │                                       │"
    echo "  │   r      Restore session              │"
    echo "  │   Enter  Restore and attach           │"
    echo "  │   R      Restore all dormant          │"
    echo "  │                                       │"
    echo "  └───────────────────────────────────────┘"
    echo ""

    # Load and show metadata if available
    if load_metadata "$session_id" 2>/dev/null; then
        echo "  Metadata:"
        [[ -n "$META_REPOSITORY_PATH" ]] && echo "    Repository: $META_REPOSITORY_PATH"
        [[ -n "$META_WORKTREE_PATH" ]] && echo "    Worktree: $META_WORKTREE_PATH"
        [[ -n "$META_CREATED_AT" ]] && echo "    Created: $META_CREATED_AT"
    fi
}

# Attach to session in default server using nested tmux
attach_to_session() {
    local session_id="$1"

    info_log "Attaching to session: $session_id"

    # Direct attach - tmux will update the screen
    # Session existence was already verified by get_session_state() in main_loop
    if [[ -f "$INNER_CONF" ]]; then
        if ! TMUX= tmux -f "$INNER_CONF" attach-session -t "$session_id" 2>&1; then
            error_log "Failed to attach: $session_id"
            show_error "Failed to attach"
            return 1
        fi
    else
        if ! TMUX= tmux attach-session -t "$session_id" 2>&1; then
            error_log "Failed to attach: $session_id"
            show_error "Failed to attach"
            return 1
        fi
    fi

    info_log "Detached from session: $session_id"
    return 0
}

# ============================================================================
# Main Loop
# ============================================================================

# Wait for update signal from list pane using tmux wait-for
# This blocks until signal is received - no polling needed
wait_for_update() {
    nav_tmux wait-for "$TOWER_VIEW_UPDATE_CHANNEL" 2>/dev/null || true
}

main_loop() {
    info_log "Starting main view loop"

    while true; do
        # Get currently selected session
        local selected
        selected=$(get_nav_selected)

        if [[ -z "$selected" ]]; then
            # No selection - show placeholder and wait for signal
            debug_log "No session selected, showing placeholder"
            show_placeholder
            wait_for_update
            continue
        fi

        debug_log "Selected session: $selected"

        # Check if session exists on DEFAULT server
        if ! TMUX= tmux has-session -t "$selected" 2>/dev/null; then
            # Session doesn't exist in tmux - check if dormant
            if has_metadata "$selected"; then
                info_log "Session is dormant: $selected"
                show_dormant_info "$selected"
            else
                debug_log "Session not found, showing placeholder"
                show_placeholder
            fi
            wait_for_update
            continue
        fi

        # Session exists - attach to it
        info_log "Attaching to session: $selected"
        if ! attach_to_session "$selected"; then
            error_log "Failed to attach to session: $selected"
            show_error "Cannot attach to session"
            wait_for_update
            continue
        fi

        # After detach (Escape pressed), loop back to check new selection
        info_log "Returned from session attachment"
    done
}

# ============================================================================
# Signal Handlers
# ============================================================================

# Cleanup on exit (placeholder for future cleanup needs)
cleanup() {
    debug_log "Navigator view pane cleanup"
}

# Combine traps: ERR for error handling, EXIT/INT/TERM for cleanup
trap 'handle_script_error $LINENO' ERR
trap cleanup EXIT INT TERM

# ============================================================================
# Main
# ============================================================================

main_loop
