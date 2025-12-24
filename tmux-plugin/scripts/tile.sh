#!/usr/bin/env bash
# tile.sh - Tile mode for claude-tower
# Shows all sessions in a grid layout for monitoring
#
# Key bindings:
#   j/↓       Move to next session
#   k/↑       Move to previous session
#   1-9       Jump to session by number
#   Enter     Attach to selected session
#   r         Refresh view
#   q/Esc     Exit tile mode

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

# Load active sessions
load_sessions() {
    SESSIONS=()
    SESSION_IDS=()

    while IFS=':' read -r session_id state type display_name branch diff_stats; do
        [[ -z "$session_id" ]] && continue
        [[ "$state" == "$STATE_DORMANT" ]] && continue  # Only active sessions

        local state_icon type_icon line
        state_icon=$(get_state_icon "$state")
        type_icon=$(get_type_icon "$type")

        line="${state_icon} ${type_icon} ${display_name}"
        [[ -n "$branch" ]] && line="${line} ${ICON_GIT}${branch}"

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
    echo -e "${BOLD}${CYAN}━━━ Tile Mode ━━━${NC}  ${DIM}j/k:nav 1-9:jump Enter:attach r:refresh q:quit${NC}"
    echo ""

    if [[ $count -eq 0 ]]; then
        echo -e "${DIM}No active sessions.${NC}"
        return
    fi

    # Calculate grid layout
    local cols=2
    local preview_height=8
    local preview_width=$(( (TERM_WIDTH - 4) / cols ))

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

        # Draw session content
        local content
        content=$(tmux capture-pane -t "$sid" -p -S -"$preview_height" 2>/dev/null | tail -"$((preview_height - 1))" || echo "(unavailable)")

        local line_num=0
        while IFS= read -r line && [[ $line_num -lt $((preview_height - 1)) ]]; do
            tput cup "$((tile_y + 1 + line_num))" "$tile_x"
            printf "${DIM}%s${NC}" "${line:0:$preview_width}"
            ((line_num++)) || true
        done <<< "$content"

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

# Handle input
handle_input() {
    local key
    read -rsn1 key

    # Handle escape sequences
    if [[ "$key" == $'\x1b' ]]; then
        read -rsn2 -t 0.1 key2 || true
        if [[ -z "$key2" ]]; then
            return 1  # Pure Escape
        fi
        key="${key}${key2}"
    fi

    local count=${#SESSIONS[@]}

    case "$key" in
        j|$'\x1b[B')  # Down / Next
            if [[ $count -gt 0 && $SELECTED_INDEX -lt $((count - 1)) ]]; then
                ((SELECTED_INDEX++)) || true
            fi
            ;;
        k|$'\x1b[A')  # Up / Previous
            if [[ $SELECTED_INDEX -gt 0 ]]; then
                ((SELECTED_INDEX--)) || true
            fi
            ;;
        [1-9])  # Number jump
            local target=$((key - 1))
            if [[ $target -lt $count ]]; then
                SELECTED_INDEX=$target
            fi
            ;;
        ""|$'\n')  # Enter - attach to selected
            if [[ $count -gt 0 ]]; then
                local selected_id="${SESSION_IDS[$SELECTED_INDEX]}"
                tput rmcup
                stty echo
                tmux switch-client -t "$selected_id" 2>/dev/null || \
                tmux attach-session -t "$selected_id" 2>/dev/null || true
                exit 0
            fi
            ;;
        r)  # Refresh
            load_sessions
            ;;
        q)  # Quit
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
