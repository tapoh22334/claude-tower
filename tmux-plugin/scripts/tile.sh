#!/usr/bin/env bash
# tile.sh - Tile view for claude-tower Navigator
# Shows all sessions in a grid layout for overview/selection
#
# Key bindings:
#   j/↓       Move to next session (wraps around)
#   k/↑       Move to previous session (wraps around)
#   g         Go to first session
#   G         Go to last session
#   1-9       Select session + return to list view
#   Enter     Return to list view with current selection
#   Tab       Return to list view
#   r         Refresh view
#   q/Esc     Quit Navigator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="tile.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Colors
readonly NC=$'\033[0m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly REVERSE=$'\033[7m'
readonly CYAN=$'\033[36m'
readonly GREEN=$'\033[32m'
readonly YELLOW=$'\033[33m'

# State
SELECTED_INDEX=0
SESSIONS=()
SESSION_IDS=()

# Quit navigator - return to caller session
quit_navigator() {
    cleanup

    local caller
    caller=$(get_nav_caller)

    # Check session server first, then default server
    if [[ -n "$caller" ]]; then
        if session_tmux has-session -t "$caller" 2>/dev/null; then
            session_tmux attach-session -t "$caller" 2>/dev/null || exit 0
        elif TMUX= tmux has-session -t "$caller" 2>/dev/null; then
            TMUX= tmux attach-session -t "$caller" 2>/dev/null || exit 0
        fi
    fi

    # Fall back to any tower session on session server
    local target
    target=$(session_tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^tower_' | head -1 || echo "")
    if [[ -n "$target" ]]; then
        session_tmux attach-session -t "$target" 2>/dev/null || exit 0
    fi

    # Final fallback to default server
    target=$(TMUX= tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")
    if [[ -n "$target" ]]; then
        TMUX= tmux attach-session -t "$target" 2>/dev/null || exit 0
    fi

    exit 0
}

# Load all sessions including dormant
load_sessions() {
    SESSIONS=()
    SESSION_IDS=()

    while IFS=':' read -r session_id state type display_name branch diff_stats; do
        [[ -z "$session_id" ]] && continue

        local state_icon type_icon line
        state_icon=$(get_state_icon "$state")
        type_icon=$(get_type_icon "$type")

        local name="${session_id#tower_}"

        # Dormant sessions shown with dim color
        if [[ "$state" == "$STATE_DORMANT" ]]; then
            line="${DIM}${state_icon} ${type_icon} ${name}${NC}"
        else
            line="${state_icon} ${type_icon} ${name}"
            [[ -n "$branch" ]] && line="${line} ${ICON_GIT}${branch}"
        fi

        SESSIONS+=("$line")
        SESSION_IDS+=("$session_id")
    done < <(list_all_sessions)

    # Adjust selected index
    local count=${#SESSIONS[@]}
    if [[ $count -eq 0 ]]; then
        SELECTED_INDEX=0
    elif [[ $SELECTED_INDEX -ge $count ]]; then
        SELECTED_INDEX=$((count - 1))
    fi
}

# Get terminal dimensions
get_dimensions() {
    TERM_HEIGHT=$(tput lines)
    TERM_WIDTH=$(tput cols)
}

# Draw tile view
draw_tiles() {
    tput clear
    get_dimensions

    local count=${#SESSIONS[@]}

    # Header
    echo -e "${BOLD}${CYAN}━━━ Tile View ━━━${NC}  ${DIM}j/k:nav g/G:first/last 1-9:select Tab:list q:quit${NC}"
    echo ""

    if [[ $count -eq 0 ]]; then
        echo -e "${DIM}No active sessions.${NC}"
        return
    fi

    # Calculate grid layout
    local cols=2
    local preview_height=8
    local preview_width=$(((TERM_WIDTH - 4) / cols))

    # Draw sessions in grid
    local row=0
    local col=0
    local idx=0

    for sid in "${SESSION_IDS[@]}"; do
        local display="${SESSIONS[$idx]}"
        local is_selected=false
        [[ $idx -eq $SELECTED_INDEX ]] && is_selected=true

        # Position cursor for this tile
        local tile_y=$((3 + row * (preview_height + 2)))
        local tile_x=$((col * (preview_width + 2)))

        # Draw tile header
        tput cup "$tile_y" "$tile_x"
        if [[ "$is_selected" == "true" ]]; then
            printf "${REVERSE}[%d] %s${NC}" "$((idx + 1))" "${display:0:$((preview_width - 5))}"
        else
            printf "${BOLD}[%d]${NC} %s" "$((idx + 1))" "${display:0:$((preview_width - 5))}"
        fi

        # Draw session content (check if dormant first)
        local content state
        state=$(get_session_state "$sid")

        if [[ "$state" == "$STATE_DORMANT" ]]; then
            content="Dormant - Press 'r' to restore"
        else
            # Capture from session server where Claude sessions live
            content=$(session_tmux capture-pane -t "$sid" -p -S -"$preview_height" 2>/dev/null | tail -"$((preview_height - 1))" || echo "(unavailable)")
        fi

        local line_num=0
        while IFS= read -r line && [[ $line_num -lt $((preview_height - 1)) ]]; do
            tput cup "$((tile_y + 1 + line_num))" "$tile_x"
            printf "${DIM}%s${NC}" "${line:0:$preview_width}"
            ((line_num++)) || true
        done <<<"$content"

        # Next tile position
        ((col++)) || true
        if [[ $col -ge $cols ]]; then
            col=0
            ((row++)) || true
        fi

        ((idx++)) || true

        # Limit visible tiles
        [[ $idx -ge 6 ]] && break
    done
}

# Return to list view with selected session
return_to_list_view() {
    local selected_id="$1"

    # Save selection to state file
    if [[ -n "$selected_id" ]]; then
        set_nav_selected "$selected_id"
    fi

    cleanup

    # Return to Navigator
    TMUX= tmux -L "$TOWER_NAV_SOCKET" attach-session -t "$TOWER_NAV_SESSION" 2>/dev/null || exit 0
    exit 0
}

# Handle input
handle_input() {
    local key
    read -rsn1 key

    # Handle escape sequences (arrow keys)
    if [[ "$key" == $'\x1b' ]]; then
        read -rsn2 -t 0.1 key2 || true
        if [[ -z "$key2" ]]; then
            # Pure Escape - ignore (use 'q' to quit)
            return 0
        fi
        key="${key}${key2}"
    fi

    local count=${#SESSIONS[@]}

    case "$key" in
        j | $'\x1b[B') # Down / Next (with wraparound)
            if [[ $count -gt 0 ]]; then
                SELECTED_INDEX=$(( (SELECTED_INDEX + 1) % count ))
            fi
            ;;
        k | $'\x1b[A') # Up / Previous (with wraparound)
            if [[ $count -gt 0 ]]; then
                SELECTED_INDEX=$(( (SELECTED_INDEX - 1 + count) % count ))
            fi
            ;;
        g) # Go to first
            SELECTED_INDEX=0
            ;;
        G) # Go to last
            if [[ $count -gt 0 ]]; then
                SELECTED_INDEX=$((count - 1))
            fi
            ;;
        [1-9]) # Number select + return to list view
            local target=$((key - 1))
            if [[ $target -lt $count ]]; then
                return_to_list_view "${SESSION_IDS[$target]}"
            fi
            ;;
        "" | $'\n') # Enter - return to list view with current selection
            if [[ $count -gt 0 ]]; then
                return_to_list_view "${SESSION_IDS[$SELECTED_INDEX]}"
            fi
            ;;
        $'\t') # Tab - return to list view
            if [[ $count -gt 0 ]]; then
                return_to_list_view "${SESSION_IDS[$SELECTED_INDEX]}"
            else
                return_to_list_view ""
            fi
            ;;
        r) # Refresh
            load_sessions
            ;;
        q) # Quit navigator
            quit_navigator
            return 1
            ;;
    esac

    return 0
}

# Cleanup
cleanup() {
    tput rmcup 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    stty echo 2>/dev/null || true
}

# Main
main() {
    trap cleanup EXIT

    tput smcup
    tput civis
    stty -echo

    load_sessions
    draw_tiles

    while true; do
        handle_input || break
        draw_tiles
    done

    cleanup
}

main
