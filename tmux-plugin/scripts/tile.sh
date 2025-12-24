#!/usr/bin/env bash
# tile.sh - Tile mode for claude-tower
# Shows all sessions in a grid layout for monitoring
#
# This creates a temporary tmux window with synchronized panes
# showing all active sessions for observation.
#
# Key bindings:
#   Esc/q    - Return to Navigator
#   1-9      - Focus on specific session

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="tile.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Tile window name
readonly TILE_WINDOW_NAME="tower-tile"

# Get list of active sessions (not dormant)
get_active_sessions() {
    while IFS=':' read -r session_id state type display_name branch diff_stats; do
        [[ -z "$session_id" ]] && continue
        [[ "$state" == "$STATE_DORMANT" ]] && continue
        echo "$session_id"
    done < <(list_all_sessions)
}

# Create tile layout
create_tile_view() {
    local sessions=()
    while IFS= read -r sid; do
        [[ -n "$sid" ]] && sessions+=("$sid")
    done < <(get_active_sessions)

    local session_count=${#sessions[@]}

    if [[ $session_count -eq 0 ]]; then
        handle_info "No active sessions to display"
        return 1
    fi

    # Get current session to return to
    local current_session
    current_session=$(tmux display-message -p '#S')

    # Create new window for tile view in a special session
    local tile_session="tower-tile-view"

    # Kill existing tile session if any
    tmux kill-session -t "$tile_session" 2>/dev/null || true

    # Create tile session
    tmux new-session -d -s "$tile_session" -n "$TILE_WINDOW_NAME"

    # Calculate grid layout
    local cols rows
    if [[ $session_count -le 2 ]]; then
        cols=2; rows=1
    elif [[ $session_count -le 4 ]]; then
        cols=2; rows=2
    elif [[ $session_count -le 6 ]]; then
        cols=3; rows=2
    elif [[ $session_count -le 9 ]]; then
        cols=3; rows=3
    else
        cols=4; rows=3
    fi

    # Create panes with session content
    local pane_idx=0
    for sid in "${sessions[@]}"; do
        if [[ $pane_idx -gt 0 ]]; then
            # Create new pane
            if [[ $((pane_idx % cols)) -eq 0 ]]; then
                # New row
                tmux split-window -t "${tile_session}:${TILE_WINDOW_NAME}" -v
            else
                # Same row
                tmux split-window -t "${tile_session}:${TILE_WINDOW_NAME}" -h
            fi
        fi

        # Set up pane to watch the session
        local pane_target="${tile_session}:${TILE_WINDOW_NAME}.${pane_idx}"
        local display_name="${sid#tower_}"

        # Use a script that captures and displays session content
        tmux send-keys -t "$pane_target" "watch -n 1 -t 'echo \"━━━ $display_name ━━━\"; tmux capture-pane -t \"$sid\" -p 2>/dev/null | tail -20 || echo \"(session unavailable)\"'" Enter

        ((pane_idx++)) || true

        # Limit to max display
        [[ $pane_idx -ge 12 ]] && break
    done

    # Balance panes
    tmux select-layout -t "${tile_session}:${TILE_WINDOW_NAME}" tiled 2>/dev/null || true

    # Set up key bindings for tile view
    # Store original session for return
    tmux set-environment -t "$tile_session" TOWER_RETURN_SESSION "$current_session"

    # Bind keys
    tmux bind-key -T root -n Escape run-shell "tmux kill-session -t '$tile_session' 2>/dev/null; tmux switch-client -t '$current_session' 2>/dev/null || true"
    tmux bind-key -T root -n q run-shell "tmux kill-session -t '$tile_session' 2>/dev/null; tmux switch-client -t '$current_session' 2>/dev/null || true"

    # Number keys to focus sessions
    local num=1
    for sid in "${sessions[@]}"; do
        tmux bind-key -T root -n "$num" run-shell "tmux kill-session -t '$tile_session' 2>/dev/null; tmux switch-client -t '$sid' 2>/dev/null || true"
        ((num++)) || true
        [[ $num -gt 9 ]] && break
    done

    # Switch to tile view
    tmux switch-client -t "$tile_session"

    # Display instructions
    handle_info "Tile mode: Press Esc/q to exit, 1-9 to focus session"
}

# Alternative: Simple text-based tile view using fzf
create_simple_tile_view() {
    local sessions=()
    while IFS= read -r sid; do
        [[ -n "$sid" ]] && sessions+=("$sid")
    done < <(get_active_sessions)

    local session_count=${#sessions[@]}

    if [[ $session_count -eq 0 ]]; then
        handle_info "No active sessions to display"
        return 1
    fi

    # Generate preview for each session
    local preview_output=""
    local idx=1

    for sid in "${sessions[@]}"; do
        local display_name="${sid#tower_}"
        local state state_icon

        state=$(get_session_state "$sid")
        state_icon=$(get_state_icon "$state")

        preview_output+="━━━ [$idx] $state_icon $display_name ━━━"$'\n'

        # Capture last few lines
        local content
        content=$(tmux capture-pane -t "$sid" -p -S -8 2>/dev/null | tail -6 || echo "(unavailable)")
        preview_output+="$content"$'\n\n'

        ((idx++)) || true
        [[ $idx -gt 9 ]] && break
    done

    # Show in fzf (read-only view)
    echo "$preview_output" | fzf-tmux -p 95%,90% \
        --ansi \
        --header="Tile View │ Press 1-9 to focus session, Esc/q to exit" \
        --prompt="" \
        --no-info \
        --bind='esc:abort,q:abort' \
        --bind='1:execute(echo 1)+abort' \
        --bind='2:execute(echo 2)+abort' \
        --bind='3:execute(echo 3)+abort' \
        --bind='4:execute(echo 4)+abort' \
        --bind='5:execute(echo 5)+abort' \
        --bind='6:execute(echo 6)+abort' \
        --bind='7:execute(echo 7)+abort' \
        --bind='8:execute(echo 8)+abort' \
        --bind='9:execute(echo 9)+abort' \
        --preview-window='hidden' \
        2>/dev/null || true

    local selected=$?

    # Handle selection (number key returns that number)
    if [[ $selected -ge 1 && $selected -le 9 ]]; then
        local target_idx=$((selected - 1))
        if [[ $target_idx -lt ${#sessions[@]} ]]; then
            local target_session="${sessions[$target_idx]}"
            tmux switch-client -t "$target_session" 2>/dev/null || \
            tmux attach-session -t "$target_session" 2>/dev/null || true
        fi
    fi
}

# Use simple tile view (more reliable)
create_simple_tile_view
