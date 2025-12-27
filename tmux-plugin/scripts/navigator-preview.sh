#!/usr/bin/env bash
# navigator-preview.sh - Right pane: Real-time preview wrapper
#
# This script runs in the right pane of Navigator.
# It connects to the selected session in the default tmux server using a nested tmux.
# When Escape is pressed, the inner tmux detaches and this script re-attaches to the
# (possibly new) selected session.
#
# The key insight: This creates a "tmux in tmux" setup where:
#   - Outer tmux: Navigator server (-L claude-tower)
#   - Inner tmux: Connection to default server's session

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ============================================================================
# Configuration
# ============================================================================

# Ensure absolute path for inner-tmux.conf (important for nested tmux)
readonly CONF_DIR="$(cd "$SCRIPT_DIR/../conf" 2>/dev/null && pwd)"
readonly INNER_CONF="$CONF_DIR/inner-tmux.conf"

# Log script startup
info_log "Navigator preview started (PID: $$)"
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
    echo "  │   Select a session to preview         │"
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
    clear
    echo ""
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
    echo "  │   Press Enter to restore and attach   │"
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

    info_log "Attempting to attach to session: $session_id"

    # Show connecting message briefly
    show_connecting "$session_id"

    # Check if session exists in DEFAULT server (TMUX= to unset Navigator context)
    if ! TMUX= tmux has-session -t "$session_id" 2>/dev/null; then
        error_log "Session not found on default server: $session_id"
        show_error "Session not found"
        return 1
    fi

    info_log "Session exists on default server, attaching with nested tmux"

    # Use nested tmux to attach to the session
    # TMUX= unsets the environment variable to allow nesting
    # -f loads our custom config that makes Escape detach
    local attach_result
    if [[ -f "$INNER_CONF" ]]; then
        info_log "Using inner-tmux.conf for nested attachment"
        if ! TMUX= tmux -f "$INNER_CONF" attach-session -t "$session_id" 2>&1; then
            error_log "Failed to attach with inner config, trying without"
            if ! TMUX= tmux attach-session -t "$session_id" 2>&1; then
                error_log "Attach failed completely"
                show_error "Failed to attach to session"
                return 1
            fi
        fi
    else
        error_log "INNER_CONF not found: $INNER_CONF"
        show_error "Config file missing"
        if ! TMUX= tmux attach-session -t "$session_id" 2>&1; then
            error_log "Attach failed without config"
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

main_loop() {
    info_log "Starting main preview loop"

    while true; do
        # Get currently selected session
        local selected
        selected=$(get_nav_selected)

        if [[ -z "$selected" ]]; then
            # No selection - show placeholder
            debug_log "No session selected, showing placeholder"
            show_placeholder
            sleep 1
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
                # Wait for signal (Escape from left pane)
                # shellcheck disable=SC2034
                read -rsn1 -t 1 _key || true
                ;;
            "")
                # Session doesn't exist
                debug_log "Session state empty, showing placeholder"
                show_placeholder
                sleep 1
                ;;
            *)
                # Active session - attach to it
                info_log "Attaching to active session: $selected (state: $state)"
                # This will block until user presses Escape (which detaches)
                if ! attach_to_session "$selected"; then
                    error_log "Failed to attach to session: $selected"
                    show_placeholder
                    sleep 1
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
    debug_log "Navigator preview cleanup"
}

trap cleanup EXIT INT TERM

# ============================================================================
# Main
# ============================================================================

main_loop
