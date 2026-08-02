#!/usr/bin/env bash
# queue-view.sh - Queue view for claude-tower Navigator
# Every Claude session that is waiting on you, oldest wait on top, so
# nothing blocked or finished gets forgotten. Visualization only — pick a
# row to jump to that session and answer it yourself.
#
# Key bindings:
#   j/↓ k/↑   Move selection (wraps)
#   g / G     First / last
#   1-9       Pick + return to list view
#   Enter/Tab Return to list view with current selection
#   q         Quit Navigator

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="queue-view.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

REFRESH_INTERVAL="${TOWER_QUEUE_REFRESH:-2}"

readonly NC=$'\033[0m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly REVERSE=$'\033[7m'
readonly CYAN=$'\033[36m'
readonly YELLOW=$'\033[33m'

readonly Q_MAX_WIDTH="${TOWER_LIST_MAX_WIDTH:-80}"
readonly Q_MIN_WIDTH="${TOWER_LIST_MIN_WIDTH:-50}"
readonly Q_AGE_COL=6

# Row label: the conversation title, or the short id when there is none.
# (Self-contained — navigator-list.sh's _session_label isn't sourced here.)
_queue_label() {
    local claude_id="${1#tower_}" title
    title=$(get_session_title "$claude_id" 2>/dev/null) || title=""
    title="${title//\\n/ }"
    title="${title//\\t/ }"
    title="${title//$'\t'/ }"
    [[ -z "$title" ]] && title="${claude_id:0:7}"
    printf '%s\n' "$title"
}

# Wait-kind -> icon. Kept here (not common.sh) since it is queue-only.
_wait_icon() {
    case "$1" in
        permission) echo "⚠" ;;
        question) echo "？" ;;
        input) echo "✱" ;;
        error) echo "✗" ;;
        *) echo "·" ;;
    esac
}

# State: parallel arrays, already ordered (longest wait first).
QUEUE_IDS=()
QUEUE_KINDS=()
QUEUE_AGES=()
SELECTED_INDEX=0

# Collect waiting sessions and order them by wait duration, longest first.
# Emits "<wait_since>\t<id>\t<kind>" per waiter, sorts numerically ascending
# on wait_since (smaller epoch = older = waited longer), fills the arrays.
load_queue() {
    QUEUE_IDS=()
    QUEUE_KINDS=()
    QUEUE_AGES=()

    local now session_id _state kind since
    now=$(date +%s)

    while IFS=$'\t' read -r since session_id kind; do
        [[ -z "$session_id" ]] && continue
        QUEUE_IDS+=("$session_id")
        QUEUE_KINDS+=("$kind")
        # "5d ago" -> "5d": the queue's age column is tight and every row
        # is an age, so the " ago" suffix is redundant noise.
        local reltime
        reltime=$(format_relative_time "$since")
        QUEUE_AGES+=("${reltime% ago}")
    done < <(
        while IFS=: read -r session_id _state; do
            [[ -z "$session_id" ]] && continue
            kind=$(get_wait_state "$session_id")
            [[ -z "$kind" ]] && continue
            since=$(wait_since "$session_id")
            printf '%s\t%s\t%s\n' "$since" "$session_id" "$kind"
        done < <(list_all_sessions) | sort -t "$(printf '\t')" -k1,1n
    )

    local count=${#QUEUE_IDS[@]}
    if [[ $count -eq 0 ]]; then
        SELECTED_INDEX=0
    elif [[ $SELECTED_INDEX -ge $count ]]; then
        SELECTED_INDEX=$((count - 1))
    fi
}

_content_width() {
    local w
    w=$(tput cols 2>/dev/null || echo 80)
    ((w > Q_MAX_WIDTH)) && w=$Q_MAX_WIDTH
    ((w < Q_MIN_WIDTH)) && w=$Q_MIN_WIDTH
    echo "$w"
}

# Compose one queue row: "<icon> <label><pad><age>", age right-aligned in a
# fixed column. Label truncated to the remaining width (display cells).
_queue_row() {
    local icon="$1" label="$2" age="$3"
    local width budget label_w pad_w
    width=$(_content_width)
    budget=$((width - 4 - Q_AGE_COL))
    ((budget < 10)) && budget=10
    label=$(truncate_display "$label" "$budget")
    label_w=$(str_display_width "$label")
    pad_w=$((width - 4 - label_w - Q_AGE_COL))
    ((pad_w < 1)) && pad_w=1
    local pad rpad age_w gap
    printf -v pad '%*s' "$pad_w" ''
    age_w=$(str_display_width "$age")
    gap=$((Q_AGE_COL - age_w))
    ((gap < 0)) && gap=0
    printf -v rpad '%*s' "$gap" ''
    printf '%s %s%s%s%s' "$icon" "$label" "$pad" "$rpad" "$age"
}

# Full frame on stdout. Last line has no trailing newline (a full-height
# frame with one scrolls every redraw — the list-view endless-scroll class).
build_queue_frame() {
    local term_height="$1" term_width="$2"
    local eol=$'\033[K'
    local count=${#QUEUE_IDS[@]}

    printf '%s' "${BOLD}${CYAN}━━━ Queue ━━━${NC}  ${DIM}j/k:nav 1-9:go Enter/Tab:list q:quit${NC}${eol}"

    if [[ $count -eq 0 ]]; then
        printf '\n%s' "${DIM}Nothing waiting — all caught up.${NC}${eol}"
        return 0
    fi

    # One row per waiter; cap to the rows that fit, collapse the rest.
    local avail=$((term_height - 2))
    ((avail < 1)) && avail=1
    local shown=$count
    if ((count > avail)); then shown=$((avail - 1)); fi
    ((shown < 1)) && shown=1

    local idx icon label row
    for ((idx = 0; idx < shown; idx++)); do
        icon=$(_wait_icon "${QUEUE_KINDS[$idx]}")
        label=$(_queue_label "${QUEUE_IDS[$idx]}")
        row=$(_queue_row "$icon" "$label" "${QUEUE_AGES[$idx]}")
        if [[ $idx -eq $SELECTED_INDEX ]]; then
            printf '\n%s' "${REVERSE}${row}${NC}${eol}"
        else
            printf '\n%s' "${row}${eol}"
        fi
    done
    if ((shown < count)); then
        printf '\n%s' "${DIM}… +$((count - shown)) more${NC}${eol}"
    fi
}

render_frame() {
    local term_height term_width frame clear_eos
    term_height=$(tput lines 2>/dev/null || echo 24)
    term_width=$(tput cols 2>/dev/null || echo 80)
    frame=$(build_queue_frame "$term_height" "$term_width")
    clear_eos=$(tput ed 2>/dev/null || printf '\033[J')
    printf '\033[?25l\033[H%b%s\033[?25h' "$frame" "$clear_eos"
}

return_to_list_view() {
    local selected_id="$1"
    [[ -n "$selected_id" ]] && set_nav_selected "$selected_id"
    cleanup
    TMUX= tmux -L "$TOWER_NAV_SOCKET" attach-session -t "$TOWER_NAV_SESSION" 2>/dev/null || exit 0
    exit 0
}

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
    local count=${#QUEUE_IDS[@]}
    case "$key" in
        j | $'\x1b[B') if ((count > 0)); then SELECTED_INDEX=$(((SELECTED_INDEX + 1) % count)); fi ;;
        k | $'\x1b[A') if ((count > 0)); then SELECTED_INDEX=$(((SELECTED_INDEX - 1 + count) % count)); fi ;;
        g) SELECTED_INDEX=0 ;;
        G) if ((count > 0)); then SELECTED_INDEX=$((count - 1)); fi ;;
        [1-9])
            local target=$((key - 1))
            if ((target < count)); then return_to_list_view "${QUEUE_IDS[$target]}"; fi
            ;;
        "" | $'\n' | $'\t')
            if ((count > 0)); then return_to_list_view "${QUEUE_IDS[$SELECTED_INDEX]}"; fi
            return_to_list_view ""
            ;;
        q) quit_navigator ;;
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

    load_queue
    render_frame

    local key key2 read_rc
    while true; do
        key=""
        read_rc=0
        # nav_read_key guards the orphaned-terminal busy-loop (rc 2 = pane gone).
        nav_read_key key "$REFRESH_INTERVAL" || read_rc=$?
        [[ $read_rc -eq 2 ]] && exit 0
        if [[ $read_rc -eq 0 ]]; then
            if [[ "$key" == $'\x1b' ]]; then
                read -rsn2 -t 0.1 key2 || true
                [[ -z "${key2:-}" ]] && continue
                key="${key}${key2}"
            fi
            handle_key "$key"
        else
            load_queue
        fi
        render_frame
    done
}

# Sourcing guard: bats sources this file to unit-test the pure functions.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
