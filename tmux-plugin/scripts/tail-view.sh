#!/usr/bin/env bash
# tail-view.sh - Tail view for claude-tower Navigator
# Live multi-session output follow: every session stacked vertically with
# the last few lines of its pane output, auto-refreshing (the point of this
# view — Tile refreshes only on keypress).
#
# Key bindings:
#   j/↓       Move to next session (wraps around)
#   k/↑       Move to previous session (wraps around)
#   g / G     Go to first / last session
#   1-9       Select session + return to list view
#   Enter     Return to list view with current selection
#   Tab       Return to list view
#   q         Quit Navigator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="tail-view.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

REFRESH_INTERVAL="${TOWER_TAIL_REFRESH:-2}"

readonly NC=$'\033[0m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly REVERSE=$'\033[7m'
readonly CYAN=$'\033[36m'

# State
SELECTED_INDEX=0
SESSION_IDS=()
SESSION_LABELS=()
SESSION_STATES=()

# Load all sessions including dormant
load_sessions() {
    SESSION_IDS=()
    SESSION_LABELS=()
    SESSION_STATES=()

    local session_id state state_icon
    while IFS=':' read -r session_id state; do
        [[ -z "$session_id" ]] && continue
        state_icon=$(get_state_icon "$state")
        SESSION_IDS+=("$session_id")
        SESSION_LABELS+=("${state_icon} ${session_id#tower_}")
        SESSION_STATES+=("$state")
    done < <(list_all_sessions)

    local count=${#SESSION_IDS[@]}
    if [[ $count -eq 0 ]]; then
        SELECTED_INDEX=0
    elif [[ $SELECTED_INDEX -ge $count ]]; then
        SELECTED_INDEX=$((count - 1))
    fi
}

# Last $2 lines of live pane output for session $1. Isolated so tests can
# stub it (capture-pane needs a live session server).
capture_tail_lines() {
    local sid="$1" n="$2"
    session_tmux capture-pane -t "$sid" -p 2>/dev/null | tail -n "$n" || true
}

# Compose one full frame on stdout. Pure layout: reads SESSION_* arrays,
# takes dimensions as arguments. Every line ends with \033[K; the LAST line
# has no trailing newline — a full-height frame with one would scroll the
# screen every redraw (the list-view endless-scroll bug class).
build_tail_frame() {
    local term_height="$1" term_width="$2"
    local eol=$'\033[K'
    local count=${#SESSION_IDS[@]}

    printf '%s' "${BOLD}${CYAN}━━━ Tail View ━━━${NC}  ${DIM}j/k:nav 1-9:select Enter/Tab:list q:quit${NC}${eol}"

    if [[ $count -eq 0 ]]; then
        printf '\n%s' "${DIM}No sessions.${NC}${eol}"
        return 0
    fi

    # Blocks share the space below the title equally, min 3 lines each
    # (1 header + 2 output). Blocks that do not fit become a "+N more" line.
    local avail=$((term_height - 1))
    local visible=$count
    if ((visible * 3 > avail)); then
        visible=$(((avail - 1) / 3))   # reserve 1 line for "+N more"
        if ((visible < 1)); then visible=1; fi
    fi
    local per_block=$((avail / visible))
    local hidden=$((count - visible))
    if ((hidden > 0)); then per_block=$(((avail - 1) / visible)); fi
    local output_lines=$((per_block - 1))

    local idx header state content line n
    for ((idx = 0; idx < visible; idx++)); do
        header="[$((idx + 1))] ${SESSION_LABELS[$idx]}"
        header="${header:0:$term_width}"
        if [[ $idx -eq $SELECTED_INDEX ]]; then
            printf '\n%s' "${REVERSE}${header}${NC}${eol}"
        else
            printf '\n%s' "${BOLD}${header}${NC}${eol}"
        fi

        state="${SESSION_STATES[$idx]}"
        case "$state" in
            "$STATE_DORMANT") content="(dormant — r in list view to resume)" ;;
            "$STATE_DEAD") content="(dead — directory is gone)" ;;
            "$STATE_LOST") content="(lost — transcript is gone)" ;;
            *) content=$(capture_tail_lines "${SESSION_IDS[$idx]}" "$output_lines") ;;
        esac

        n=0
        while IFS= read -r line && ((n < output_lines)); do
            printf '\n%s' "  ${DIM}${line:0:$((term_width - 2))}${NC}${eol}"
            n=$((n + 1))
        done <<<"$content"
        while ((n < output_lines)); do
            printf '\n%s' "$eol"
            n=$((n + 1))
        done
    done

    if ((hidden > 0)); then
        printf '\n%s' "${DIM}+${hidden} more${NC}${eol}"
    fi
}

render_frame() {
    local term_height term_width frame clear_eos
    term_height=$(tput lines 2>/dev/null || echo 24)
    term_width=$(tput cols 2>/dev/null || echo 80)
    frame=$(build_tail_frame "$term_height" "$term_width")
    clear_eos=$(tput ed 2>/dev/null || printf '\033[J')
    printf '\033[?25l\033[H%b%s\033[?25h' "$frame" "$clear_eos"
}

# Return to list view with selected session
return_to_list_view() {
    local selected_id="$1"
    [[ -n "$selected_id" ]] && set_nav_selected "$selected_id"
    cleanup
    TMUX= tmux -L "$TOWER_NAV_SOCKET" attach-session -t "$TOWER_NAV_SESSION" 2>/dev/null || exit 0
    exit 0
}

# Quit navigator - return to caller session (same handoff as tile.sh)
quit_navigator() {
    cleanup

    local caller
    caller=$(get_nav_caller)
    if [[ -n "$caller" ]]; then
        if session_tmux has-session -t "$caller" 2>/dev/null; then
            session_tmux attach-session -t "$caller" 2>/dev/null || exit 0
        elif TMUX= tmux has-session -t "$caller" 2>/dev/null; then
            TMUX= tmux attach-session -t "$caller" 2>/dev/null || exit 0
        fi
    fi

    local target
    target=$(session_tmux list-sessions -F '#{session_name}' 2>/dev/null | grep '^tower_' | head -1 || echo "")
    if [[ -n "$target" ]]; then
        session_tmux attach-session -t "$target" 2>/dev/null || exit 0
    fi
    target=$(TMUX= tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")
    if [[ -n "$target" ]]; then
        TMUX= tmux attach-session -t "$target" 2>/dev/null || exit 0
    fi
    exit 0
}

handle_key() {
    local key="$1"
    local count=${#SESSION_IDS[@]}

    case "$key" in
        j | $'\x1b[B')
            if ((count > 0)); then SELECTED_INDEX=$(((SELECTED_INDEX + 1) % count)); fi
            ;;
        k | $'\x1b[A')
            if ((count > 0)); then SELECTED_INDEX=$(((SELECTED_INDEX - 1 + count) % count)); fi
            ;;
        g)
            SELECTED_INDEX=0
            ;;
        G)
            if ((count > 0)); then SELECTED_INDEX=$((count - 1)); fi
            ;;
        [1-9])
            local target=$((key - 1))
            if ((target < count)); then return_to_list_view "${SESSION_IDS[$target]}"; fi
            ;;
        "" | $'\n' | $'\t')
            if ((count > 0)); then
                return_to_list_view "${SESSION_IDS[$SELECTED_INDEX]}"
            fi
            return_to_list_view ""
            ;;
        q)
            quit_navigator
            ;;
    esac
    return 0
}

cleanup() {
    tput rmcup 2>/dev/null || true
    tput cnorm 2>/dev/null || true
    stty echo 2>/dev/null || true
}

main() {
    trap cleanup EXIT
    tput smcup 2>/dev/null || true
    tput civis 2>/dev/null || true
    stty -echo 2>/dev/null || true

    load_sessions
    render_frame

    local key key2
    while true; do
        key=""
        if read -rsn1 -t "$REFRESH_INTERVAL" key; then
            if [[ "$key" == $'\x1b' ]]; then
                read -rsn2 -t 0.1 key2 || true
                [[ -z "${key2:-}" ]] && continue
                key="${key}${key2}"
            fi
            handle_key "$key"
        else
            # Timeout: this is the tail part — reload and follow.
            load_sessions
        fi
        render_frame
    done
}

# Sourcing guard: bats sources this file to unit-test the pure functions.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
