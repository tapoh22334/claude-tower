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

readonly CONF_DIR="$SCRIPT_DIR/../conf"
readonly INNER_CONF="$CONF_DIR/inner-tmux.conf"

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
    echo "  │   Press 'i' to interact               │"
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

    # Check if session exists in default server
    if ! tmux has-session -t "$session_id" 2>/dev/null; then
        return 1
    fi

    # Use nested tmux to attach to the session
    # TMUX= unsets the environment variable to allow nesting
    # -f loads our custom config that makes Escape detach
    if [[ -f "$INNER_CONF" ]]; then
        TMUX= tmux -f "$INNER_CONF" attach-session -t "$session_id"
    else
        # Fallback: attach with just escape binding
        TMUX= tmux attach-session -t "$session_id"
    fi
}

# ============================================================================
# Main Loop
# ============================================================================

main_loop() {
    while true; do
        # Get currently selected session
        local selected
        selected=$(get_nav_selected)

        if [[ -z "$selected" ]]; then
            # No selection - show placeholder
            show_placeholder
            sleep 1
            continue
        fi

        # Check session state
        local state
        state=$(get_session_state "$selected")

        case "$state" in
            "$STATE_DORMANT")
                # Show dormant info
                show_dormant_info "$selected"
                # Wait for signal (Escape from left pane)
                read -rsn1 -t 1 key || true
                ;;
            "")
                # Session doesn't exist
                show_placeholder
                sleep 1
                ;;
            *)
                # Active session - attach to it
                # This will block until user presses Escape (which detaches)
                if ! attach_to_session "$selected"; then
                    show_placeholder
                    sleep 1
                fi
                # After detach, loop back to check new selection
                ;;
        esac
    done
}

# ============================================================================
# Signal Handlers
# ============================================================================

# Handle Escape key gracefully
handle_escape() {
    # Just continue the loop - will re-read selection
    :
}

# Cleanup on exit
cleanup() {
    # Nothing special needed
    :
}

trap cleanup EXIT

# ============================================================================
# Main
# ============================================================================

main_loop
