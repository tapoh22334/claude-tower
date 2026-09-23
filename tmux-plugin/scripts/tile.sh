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
    # Hand the outer client to the caller (detach -E), then let this window
    # close. Never attach from inside this pane — see view_quit_navigator.
    view_quit_navigator
    exit 0
}

# Load all sessions including dormant
load_sessions() {
    SESSIONS=()
    SESSION_IDS=()

    while IFS=':' read -r session_id state; do
        [[ -z "$session_id" ]] && continue

        local state_icon line
        state_icon=$(get_state_icon "$state")

        local name="${session_id#tower_}"

        # Dormant sessions shown with dim color
        if [[ "$state" == "$STATE_DORMANT" ]]; then
            line="${DIM}${state_icon} ${name}${NC}"
        else
            line="${state_icon} ${name}"
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
    TERM_HEIGHT=$(_term_lines)
    TERM_WIDTH=$(_term_cols)
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

        # Limit visible tiles. Written as `if ... ; then break; fi` rather
        # than `[[ ... ]] && break`: the latter's exit status is 1 whenever
        # the condition is false (the common case, tile count < 6), which
        # under this script's `set -e` was silently killing the whole
        # process right after the first draw_tiles call in main() -- the
        # tile view drew one frame and exited before ever reading a
        # keypress. Caught via real capture-pane testing in Docker.
        if [[ $idx -ge 6 ]]; then
            break
        fi
    done
}


# Start with the cursor on the session the list had selected, when it is in
# this view; otherwise on the first row. Without this, Enter handed the list
# the FIRST session whatever the user had been on — the selection was lost
# every time the view was opened and closed (#31).
_seed_selection() {
    local current i
    current=$(get_nav_selected)
    [[ -n "$current" ]] || return 0
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        if [[ "${SESSION_IDS[$i]}" == "$current" ]]; then
            SELECTED_INDEX=$i
            return 0
        fi
    done
    return 0
}

# Return to list view with selected session (hand the outer client back)
return_to_list_view() {
    local selected_id="$1"
    [[ -n "$selected_id" ]] && set_nav_selected "$selected_id"
    cleanup
    # Detach the outer client onto the Navigator; this window closes when we
    # exit. An attach from inside this pane would nest the Navigator (#37).
    view_return_to_navigator
    exit 0
}

# Handle input
handle_input() {
    local key
    # A blocking read normally can't busy-loop, but if the terminal vanishes
    # (orphaned after the tmux client/server died) read returns EOF instantly
    # every call, spinning the main loop. Return non-zero on EOF so the caller
    # breaks out instead of spinning.
    read -rsn1 key || return 1

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
    _seed_selection
    draw_tiles

    while true; do
        handle_input || break
        draw_tiles
    done

    cleanup
}

main
