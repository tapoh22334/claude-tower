#!/usr/bin/env bash
# navigator.sh - Sidebar-style Navigator UI for claude-tower
# Shows session list on left, preview on right
#
# Key bindings:
#   j / ↓     - Move down
#   k / ↑     - Move up
#   Enter     - Attach to selected session
#   i         - Input mode (send command to session)
#   t         - Switch to Tile mode
#   n         - Create new session
#   d         - Delete session
#   r         - Restart Claude in session
#   ?         - Show help
#   q / Esc   - Exit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="navigator.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Navigator state
SELECTED_INDEX=0
SESSIONS=()
SESSION_IDS=()

# Colors for TUI (no background, just foreground)
readonly NC=$'\033[0m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly REVERSE=$'\033[7m'
readonly CYAN=$'\033[36m'
readonly GREEN=$'\033[32m'
readonly YELLOW=$'\033[33m'
readonly RED=$'\033[31m'
readonly BLUE=$'\033[34m'

# Load sessions into arrays
load_sessions() {
    SESSIONS=()
    SESSION_IDS=()

    while IFS=':' read -r session_id state type display_name branch diff_stats; do
        [[ -z "$session_id" ]] && continue

        local state_icon type_icon line
        state_icon=$(get_state_icon "$state")
        type_icon=$(get_type_icon "$type")

        # Build display line
        line="${state_icon} ${type_icon} ${display_name}"
        [[ -n "$branch" ]] && line="${line}  ${ICON_GIT} ${branch}"
        [[ -n "$diff_stats" ]] && line="${line}  ${diff_stats}"

        SESSIONS+=("$line")
        SESSION_IDS+=("$session_id")
    done < <(list_all_sessions)

    # Adjust selected index if out of bounds
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

    # Calculate pane sizes (left sidebar ~35%, right preview ~65%)
    SIDEBAR_WIDTH=$((TERM_WIDTH * 35 / 100))
    [[ $SIDEBAR_WIDTH -lt 30 ]] && SIDEBAR_WIDTH=30
    [[ $SIDEBAR_WIDTH -gt 50 ]] && SIDEBAR_WIDTH=50

    PREVIEW_WIDTH=$((TERM_WIDTH - SIDEBAR_WIDTH - 3))
    LIST_HEIGHT=$((TERM_HEIGHT - 6))
}

# Draw a box border
draw_box() {
    local x=$1 y=$2 w=$3 h=$4 title="${5:-}"

    # Top border
    tput cup "$y" "$x"
    printf "┌─"
    [[ -n "$title" ]] && printf " %s " "$title"
    local title_len=${#title}
    [[ -n "$title" ]] && title_len=$((title_len + 2))
    local remaining=$((w - 4 - title_len))
    printf "%*s" "$remaining" "" | tr ' ' '─'
    printf "┐"

    # Side borders
    for ((i = 1; i < h - 1; i++)); do
        tput cup "$((y + i))" "$x"
        printf "│"
        tput cup "$((y + i))" "$((x + w - 1))"
        printf "│"
    done

    # Bottom border
    tput cup "$((y + h - 1))" "$x"
    printf "└"
    printf "%*s" "$((w - 2))" "" | tr ' ' '─'
    printf "┘"
}

# Draw sidebar with session list
draw_sidebar() {
    local x=0 y=0 w=$SIDEBAR_WIDTH h=$((TERM_HEIGHT - 3))

    draw_box "$x" "$y" "$w" "$h" "Sessions"

    local count=${#SESSIONS[@]}
    local visible_start=0
    local visible_count=$((h - 4))

    # Scroll if needed
    if [[ $SELECTED_INDEX -ge $visible_count ]]; then
        visible_start=$((SELECTED_INDEX - visible_count + 1))
    fi

    # Draw session list
    for ((i = 0; i < visible_count && (visible_start + i) < count; i++)); do
        local idx=$((visible_start + i))
        local line="${SESSIONS[$idx]}"
        local display_width=$((w - 4))

        # Truncate if too long
        if [[ ${#line} -gt $display_width ]]; then
            line="${line:0:$((display_width - 1))}…"
        fi

        tput cup "$((y + 1 + i))" "$((x + 2))"

        if [[ $idx -eq $SELECTED_INDEX ]]; then
            printf "${REVERSE}%-${display_width}s${NC}" "$line"
        else
            printf "%-${display_width}s" "$line"
        fi
    done

    # Clear remaining lines
    for ((i = count - visible_start; i < visible_count; i++)); do
        tput cup "$((y + 1 + i))" "$((x + 2))"
        printf "%*s" "$((w - 4))" ""
    done

    # Draw git info for selected session
    if [[ $count -gt 0 ]]; then
        local selected_id="${SESSION_IDS[$SELECTED_INDEX]}"
        local git_line=""

        # Get working directory and branch
        local state working_dir branch
        state=$(get_session_state "$selected_id")

        if [[ "$state" != "$STATE_DORMANT" ]]; then
            working_dir=$(tmux display-message -t "$selected_id" -p '#{pane_current_path}' 2>/dev/null || echo "")
        elif load_metadata "$selected_id" 2>/dev/null; then
            working_dir="$META_WORKTREE_PATH"
        fi

        if [[ -n "$working_dir" && -d "$working_dir" ]]; then
            if git -C "$working_dir" rev-parse --git-dir &>/dev/null; then
                branch=$(git -C "$working_dir" branch --show-current 2>/dev/null || echo "detached")
                local stats
                stats=$(git -C "$working_dir" diff --shortstat 2>/dev/null | sed 's/^ *//')
                git_line="${ICON_GIT} ${branch}"
                [[ -n "$stats" ]] && git_line="${git_line}  ${stats}"
            fi
        fi

        # Draw separator and git info
        tput cup "$((h - 3))" "$x"
        printf "├"
        printf "%*s" "$((w - 2))" "" | tr ' ' '─'
        printf "┤"

        tput cup "$((h - 2))" "$((x + 2))"
        printf "${YELLOW}%-$((w - 4))s${NC}" "${git_line:0:$((w - 4))}"
    fi

    # Draw help line
    tput cup "$((TERM_HEIGHT - 2))" 0
    printf "${DIM}j/k:move  Enter:attach  i:input  t:tile  n:new  d:delete  r:restart  ?:help  q:quit${NC}"
}

# Draw preview pane
draw_preview() {
    local x=$((SIDEBAR_WIDTH + 1)) y=0 w=$((TERM_WIDTH - SIDEBAR_WIDTH - 1)) h=$((TERM_HEIGHT - 3))

    draw_box "$x" "$y" "$w" "$h" "Preview"

    local count=${#SESSIONS[@]}
    if [[ $count -eq 0 ]]; then
        tput cup "$((y + 2))" "$((x + 2))"
        printf "${DIM}No sessions. Press 'n' to create one.${NC}"
        return
    fi

    local selected_id="${SESSION_IDS[$SELECTED_INDEX]}"
    local state
    state=$(get_session_state "$selected_id")

    # Show session info
    tput cup "$((y + 1))" "$((x + 2))"
    local type type_icon state_icon
    type=$(get_session_type "$selected_id")
    type_icon=$(get_type_icon "$type")
    state_icon=$(get_state_icon "$state")
    printf "${CYAN}%s${NC} %s %s  ${DIM}%s${NC}" "$state_icon" "$type_icon" "${selected_id#tower_}" "$state"

    # Show pane content
    tput cup "$((y + 3))" "$((x + 2))"
    printf "${DIM}─── Output ───${NC}"

    if [[ "$state" == "$STATE_DORMANT" ]]; then
        tput cup "$((y + 5))" "$((x + 2))"
        printf "${YELLOW}Session is dormant. Press Enter to restore.${NC}"
    else
        # Capture and display pane content
        local content_height=$((h - 6))
        local content_width=$((w - 4))
        local content
        content=$(tmux capture-pane -t "$selected_id" -p -S -"$content_height" 2>/dev/null | tail -"$content_height" || echo "(no output)")

        local line_num=0
        while IFS= read -r line && [[ $line_num -lt $content_height ]]; do
            tput cup "$((y + 4 + line_num))" "$((x + 2))"
            # Truncate line and remove problematic characters
            line="${line:0:$content_width}"
            printf "%s" "$line"
            ((line_num++)) || true
        done <<< "$content"
    fi
}

# Draw full screen
draw_screen() {
    tput clear
    get_dimensions
    draw_sidebar
    draw_preview
}

# Handle input
handle_input() {
    local key
    read -rsn1 key

    # Handle escape sequences (arrow keys)
    if [[ "$key" == $'\x1b' ]]; then
        read -rsn2 -t 0.1 key2 || true
        if [[ -z "$key2" ]]; then
            # Pure Escape key (no sequence) = quit
            return 1
        fi
        key="${key}${key2}"
    fi

    local count=${#SESSIONS[@]}

    case "$key" in
        j|$'\x1b[B')  # Down
            if [[ $count -gt 0 && $SELECTED_INDEX -lt $((count - 1)) ]]; then
                ((SELECTED_INDEX++)) || true
            fi
            ;;
        k|$'\x1b[A')  # Up
            if [[ $SELECTED_INDEX -gt 0 ]]; then
                ((SELECTED_INDEX--)) || true
            fi
            ;;
        ""|$'\n')  # Enter
            if [[ $count -gt 0 ]]; then
                local selected_id="${SESSION_IDS[$SELECTED_INDEX]}"
                local state
                state=$(get_session_state "$selected_id")

                # Restore terminal before switching
                tput rmcup
                stty echo

                if [[ "$state" == "$STATE_DORMANT" ]]; then
                    restore_session "$selected_id"
                fi

                tmux switch-client -t "$selected_id" 2>/dev/null || \
                tmux attach-session -t "$selected_id" 2>/dev/null || true
                exit 0
            fi
            ;;
        i)  # Input mode
            if [[ $count -gt 0 ]]; then
                local selected_id="${SESSION_IDS[$SELECTED_INDEX]}"
                tput rmcup
                stty echo
                "$SCRIPT_DIR/input.sh" "$selected_id"
                exit 0
            fi
            ;;
        t)  # Tile mode
            tput rmcup
            stty echo
            "$SCRIPT_DIR/tile.sh"
            exit 0
            ;;
        n)  # New session
            tput rmcup
            stty echo
            "$SCRIPT_DIR/session-new.sh"
            exit 0
            ;;
        d)  # Delete session
            if [[ $count -gt 0 ]]; then
                local selected_id="${SESSION_IDS[$SELECTED_INDEX]}"
                tput rmcup
                stty echo
                "$SCRIPT_DIR/session-delete.sh" "$selected_id"
                # Restart navigator
                exec "$0"
            fi
            ;;
        r)  # Restart session
            if [[ $count -gt 0 ]]; then
                local selected_id="${SESSION_IDS[$SELECTED_INDEX]}"
                restart_session "$selected_id"
                load_sessions
            fi
            ;;
        "?")  # Help
            show_help
            ;;
        q)  # Quit
            return 1
            ;;
    esac

    return 0
}

# Show help overlay
show_help() {
    tput clear
    cat << 'EOF'

  ╔══════════════════════════════════════════════════════╗
  ║               claude-tower Navigator                 ║
  ╠══════════════════════════════════════════════════════╣
  ║                                                      ║
  ║  Navigation:                                         ║
  ║    j / ↓      Move down                              ║
  ║    k / ↑      Move up                                ║
  ║    Enter      Attach to selected session             ║
  ║    q / Esc    Exit Navigator                         ║
  ║                                                      ║
  ║  Actions:                                            ║
  ║    i          Input mode (send command)              ║
  ║    t          Tile mode (view all sessions)          ║
  ║    n          New session                            ║
  ║    d          Delete session                         ║
  ║    r          Restart Claude                         ║
  ║    ?          Show this help                         ║
  ║                                                      ║
  ║  Session States:                                     ║
  ║    ◉ Running  Claude is actively working             ║
  ║    ▶ Idle     Claude is waiting for input            ║
  ║    ! Exited   Claude process has exited              ║
  ║    ○ Dormant  Session needs restoration              ║
  ║                                                      ║
  ║  Session Types:                                      ║
  ║    [W] Worktree  Persistent (auto-restores)          ║
  ║    [S] Simple    Volatile (lost on restart)          ║
  ║                                                      ║
  ║  Press any key to close                              ║
  ╚══════════════════════════════════════════════════════╝

EOF
    read -rsn1
}

# Cleanup on exit
cleanup() {
    tput rmcup 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    stty echo 2>/dev/null || true
}

# Main loop
main() {
    trap cleanup EXIT

    # Enter alternate screen buffer
    tput smcup
    tput civis  # Hide cursor
    stty -echo

    load_sessions
    draw_screen

    # Main loop
    while true; do
        handle_input || break
        load_sessions
        draw_screen
    done

    cleanup
}

main
