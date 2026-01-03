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

# Track last known selection for change detection
LAST_SELECTED=""
SIGNAL_FILE="${TOWER_NAV_STATE_DIR}/view_signal"
LAST_SIGNAL=""

# Check if selection changed
selection_changed() {
    local current_selected
    current_selected=$(get_nav_selected)

    # Check signal file for forced update
    local current_signal=""
    [[ -f "$SIGNAL_FILE" ]] && current_signal=$(cat "$SIGNAL_FILE" 2>/dev/null || echo "")

    if [[ "$current_selected" != "$LAST_SELECTED" ]] || [[ "$current_signal" != "$LAST_SIGNAL" ]]; then
        LAST_SELECTED="$current_selected"
        LAST_SIGNAL="$current_signal"
        return 0  # Changed
    fi
    return 1  # Not changed
}

main_loop() {
    info_log "Starting main view loop"

    while true; do
        # Get currently selected session
        local selected
        selected=$(get_nav_selected)
        LAST_SELECTED="$selected"
        [[ -f "$SIGNAL_FILE" ]] && LAST_SIGNAL=$(cat "$SIGNAL_FILE" 2>/dev/null || echo "")

        if [[ -z "$selected" ]]; then
            # No selection - show placeholder
            debug_log "No session selected, showing placeholder"
            show_placeholder
            sleep 0.5
            continue
        fi

        debug_log "Selected session: $selected"

        # Check session state (on DEFAULT server)
        local state
        state=$(get_session_state "$selected")

        debug_log "Session state: $state"

        case "$state" in
            "$STATE_DORMANT")
                # Show dormant info
                info_log "Session is dormant: $selected"
                show_dormant_info "$selected"
                # Poll for selection change (short interval)
                while ! selection_changed; do
                    sleep 0.2
                done
                ;;
            "")
                # Session doesn't exist
                debug_log "Session state empty, showing placeholder"
                show_placeholder
                # Poll for selection change
                while ! selection_changed; do
                    sleep 0.3
                done
                ;;
            *)
                # Active session - attach to it
                info_log "Attaching to active session: $selected (state: $state)"
                # This will block until user presses Escape (which detaches)
                if ! attach_to_session "$selected"; then
                    error_log "Failed to attach to session: $selected"
                    show_placeholder
                    sleep 0.5
                fi
                # After detach, loop back to check new selection
                info_log "Returned from session attachment, checking for new selection"
                ;;
        esac
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
