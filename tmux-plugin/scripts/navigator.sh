#!/usr/bin/env bash
# navigator.sh - Session navigator using gum
# Fast and simple UI with gum

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Check for gum
if ! command -v gum &>/dev/null; then
    echo "Error: gum is required. Install with: brew install gum"
    exit 1
fi

# Build session list for display
build_session_list() {
    local sessions=()

    while IFS=: read -r id state type; do
        [[ -z "$id" ]] && continue

        local icon type_icon name
        icon=$(get_state_icon "$state")
        type_icon=$(get_type_icon "$type")
        name="${id#tower_}"

        sessions+=("$icon $type_icon $name")
    done < <(list_all_sessions 2>/dev/null)

    printf '%s\n' "${sessions[@]}"
}

# Build session ID list (parallel to display list)
build_session_ids() {
    while IFS=: read -r id state type; do
        [[ -z "$id" ]] && continue
        echo "$id"
    done < <(list_all_sessions 2>/dev/null)
}

# Show preview of selected session
show_preview() {
    local session_id="$1"
    local state
    state=$(get_session_state "$session_id")

    echo "━━━ Preview: ${session_id#tower_} ━━━"
    echo ""

    if [[ "$state" == "$STATE_DORMANT" ]]; then
        gum style --foreground 214 "(Session is dormant - will restore on attach)"
        if load_metadata "$session_id" 2>/dev/null; then
            echo "Worktree: $META_WORKTREE_PATH"
        fi
    else
        tmux capture-pane -t "$session_id" -p -S -20 2>/dev/null | tail -15 || echo "(no output)"
    fi
}

# Main menu
main_menu() {
    while true; do
        # Get sessions
        local display_list id_list
        display_list=$(build_session_list)
        id_list=$(build_session_ids)

        if [[ -z "$display_list" ]]; then
            gum style --foreground 214 "No sessions found."

            if gum confirm "Create a new session?"; then
                "$SCRIPT_DIR/session-new.sh"
                continue
            else
                exit 0
            fi
        fi

        # Convert to arrays
        mapfile -t displays <<< "$display_list"
        mapfile -t ids <<< "$id_list"

        # Show session picker with filter
        local selected
        selected=$(printf '%s\n' "${displays[@]}" | \
            gum filter --placeholder "Search sessions..." \
                       --header "Sessions (Enter=attach, Ctrl+C=menu)" \
                       --height 15 \
                       --indicator "▶" \
                       --indicator.foreground 212) || true

        [[ -z "$selected" ]] && break

        # Find the session ID for selected display
        local selected_id=""
        for i in "${!displays[@]}"; do
            if [[ "${displays[$i]}" == "$selected" ]]; then
                selected_id="${ids[$i]}"
                break
            fi
        done

        [[ -z "$selected_id" ]] && continue

        # Show action menu
        clear
        show_preview "$selected_id"
        echo ""

        local action
        action=$(gum choose --header "Action for: ${selected_id#tower_}" \
            "attach    → Switch to session" \
            "input     → Send command" \
            "tile      → View all sessions" \
            "new       → Create new session" \
            "delete    → Delete session" \
            "restart   → Restart Claude" \
            "back      → Back to list" \
            "quit      → Exit navigator") || action="back"

        case "$action" in
            "attach"*)
                local state
                state=$(get_session_state "$selected_id")
                if [[ "$state" == "$STATE_DORMANT" ]]; then
                    gum spin --spinner dot --title "Restoring session..." -- \
                        "$SCRIPT_DIR/session-restore.sh" "$selected_id"
                fi
                tmux switch-client -t "$selected_id"
                exit 0
                ;;
            "input"*)
                local input
                input=$(gum input --placeholder "Enter command to send..." --width 60) || true
                if [[ -n "$input" ]]; then
                    tmux send-keys -t "$selected_id" "$input" Enter
                    gum spin --spinner dot --title "Sending..." -- sleep 0.5
                fi
                ;;
            "tile"*)
                "$SCRIPT_DIR/tile.sh"
                exit 0
                ;;
            "new"*)
                "$SCRIPT_DIR/session-new.sh"
                ;;
            "delete"*)
                if gum confirm "Delete session '${selected_id#tower_}'?"; then
                    "$SCRIPT_DIR/session-delete.sh" "$selected_id" --force 2>/dev/null || true
                    gum style --foreground 212 "Deleted."
                    sleep 0.5
                fi
                ;;
            "restart"*)
                tmux send-keys -t "$selected_id" C-c
                sleep 0.2
                tmux send-keys -t "$selected_id" "${CLAUDE_TOWER_PROGRAM:-claude}" Enter
                gum style --foreground 212 "Restarted."
                sleep 0.5
                ;;
            "quit"*)
                exit 0
                ;;
        esac
    done
}

# Run
main_menu
