#!/usr/bin/env bash
# tail-view.sh - Tail view for claude-tower Navigator
# The end of each session's conversation, stacked vertically and
# auto-refreshing (the point of this view — Tile refreshes only on keypress).
#
# Which sessions: the queue's, in the queue's order (most recent wait
# first), then the rest by most recent activity, so the blocks that fit are
# the ones you are about to answer. What each block shows: the last messages
# of the conversation from the transcript, not the pane — the bottom of a
# Claude pane is its input box and status line, which say nothing about
# where the session is. The pane is the fallback when there is no
# transcript (yet) or no jq.
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
# shellcheck source=../lib/queue.sh
source "$SCRIPT_DIR/../lib/queue.sh"

REFRESH_INTERVAL="${TOWER_TAIL_REFRESH:-2}"
# Lines of conversation kept per block; a block shows the last of them that
# fit. More than any block gets on a normal screen.
readonly TAIL_KEEP_LINES=60

readonly NC=$'\033[0m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly REVERSE=$'\033[7m'
readonly CYAN=$'\033[36m'
readonly DEFAULT_FG=$'\033[39m'
readonly PROJECT_FG=$'\033[35m'

# State
SELECTED_INDEX=0
SELECTED_ID=""
SESSION_IDS=()
SESSION_LABELS=()
SESSION_STATES=()
# Conversation tail per block, filled for the blocks that fit. An unset
# entry means "no transcript to show": the frame falls back to the pane.
SESSION_TAILS=()
# The load's scratch dir, so cleanup removes it if the pane dies mid-load.
TAIL_TMP_DIR=""

# Lines a block gets at least: 1 header + 4 of conversation. Two lines (the
# old floor) hold half a sentence of a reply, too little to tell where the
# session is; fewer, readable blocks are worth more, and the queue order
# puts the ones that matter first.
readonly TAIL_MIN_BLOCK=5

# Blocks that fit in a $1-line terminal for $2 sessions: blocks share the
# space below the title, at least TAIL_MIN_BLOCK lines each, with one line
# kept for "+N more" when some do not fit.
_visible_blocks() {
    local term_height="$1" count="$2"
    local avail=$((term_height - 1)) visible=$count
    if ((visible * TAIL_MIN_BLOCK > avail)); then
        visible=$(((avail - 1) / TAIL_MIN_BLOCK))
        ((visible < 1)) && visible=1
    fi
    ((visible > count)) && visible=$count
    echo "$visible"
}

# Load the sessions in queue order, then their states and conversation
# tails for the blocks that fit.
load_sessions() {
    SESSION_IDS=()
    SESSION_LABELS=()
    SESSION_STATES=()
    SESSION_TAILS=()

    local since session_id kind project label icon cols
    cols=$(_term_cols)
    while IFS=$'\t' read -r since session_id kind project label; do
        [[ -z "$session_id" ]] && continue
        icon=$(_wait_icon "$kind")
        # "[N] I project  title": keep the header on one line.
        label=$(truncate_display "$label" $((cols - 9 - $(str_display_width "$project"))))
        SESSION_IDS+=("$session_id")
        SESSION_LABELS+=("$(_wait_color "$kind")${icon}${DEFAULT_FG} ${PROJECT_FG}${project}${DEFAULT_FG}  ${label}")
        SESSION_STATES+=("")
    done < <(collect_queue all)

    local count=${#SESSION_IDS[@]}
    if [[ $count -eq 0 ]]; then
        SELECTED_INDEX=0
    elif [[ $SELECTED_INDEX -ge $count ]]; then
        SELECTED_INDEX=$((count - 1))
    fi
    # The list is rebuilt every refresh and its order can change under the
    # cursor (a session starting to wait moves to the top). Keep the cursor
    # on the same id, not the same row number.
    if [[ -n "${SELECTED_ID:-}" ]]; then
        local i
        for ((i = 0; i < count; i++)); do
            if [[ "${SESSION_IDS[$i]}" == "$SELECTED_ID" ]]; then
                SELECTED_INDEX=$i
                break
            fi
        done
    fi
    ((count > 0)) && SELECTED_ID="${SESSION_IDS[$SELECTED_INDEX]}"
    _load_visible_tails
    return 0
}

# States and conversation tails for the blocks that fit, read in parallel:
# each tail parses a slice of a transcript (~0.1s), and one after another
# they would hold up every refresh. Call it bare, not under $(...).
_load_visible_tails() {
    local count=${#SESSION_IDS[@]}
    ((count > 0)) || return 0
    local visible width dir i
    visible=$(_visible_blocks "$(_term_lines)" "$count")
    width=$(($(_term_cols) - 2))
    dir=$(mktemp -d "${TMPDIR:-/tmp}/tower-tail.XXXXXX") || return 0
    TAIL_TMP_DIR="$dir"
    for ((i = 0; i < visible; i++)); do
        (
            local sid="${SESSION_IDS[$i]}" jsonl
            get_display_state "$sid" >"$dir/state.$i" 2>/dev/null
            jsonl=$(find_session_jsonl "$(live_claude_id "$sid")" 2>/dev/null) || exit 0
            transcript_tail "$jsonl" "$TAIL_KEEP_LINES" "$width" >"$dir/tail.$i" 2>/dev/null ||
                rm -f "$dir/tail.$i"
        ) &
    done
    wait
    for ((i = 0; i < visible; i++)); do
        [[ -f "$dir/state.$i" ]] && SESSION_STATES[i]=$(<"$dir/state.$i")
        [[ -f "$dir/tail.$i" ]] && SESSION_TAILS[i]=$(<"$dir/tail.$i")
    done
    rm -rf "$dir"
    TAIL_TMP_DIR=""
}

# Last $2 lines of live pane output for session $1. Isolated so tests can
# stub it (capture-pane needs a live session server).
capture_tail_lines() {
    local sid="$1" n="$2"
    session_tmux capture-pane -t "$sid" -p 2>/dev/null | grep -v '^[[:space:]]*$' | tail -n "$n" || true
}

# Compose one full frame on stdout. Pure layout: reads SESSION_* arrays,
# takes dimensions as arguments. Every line ends with \033[K; the LAST line
# has no trailing newline — a full-height frame with one would scroll the
# screen every redraw (the list-view endless-scroll bug class).
build_tail_frame() {
    local term_height="$1" term_width="$2"
    local eol=$'\033[K'
    local count=${#SESSION_IDS[@]}

    printf '%s' "${BOLD}${CYAN}━━━ Tail View ━━━${NC}  ${DIM}j/k move  1-9 open  Enter list  q quit${NC}${eol}"

    if [[ $count -eq 0 ]]; then
        printf '\n%s' "${DIM}No sessions.${NC}${eol}"
        return 0
    fi

    local avail=$((term_height - 1))
    local visible
    visible=$(_visible_blocks "$term_height" "$count")
    local hidden=$((count - visible))
    local per_block=$((avail / visible))
    if ((hidden > 0)); then per_block=$(((avail - 1) / visible)); fi
    local output_lines=$((per_block - 1))

    local idx header num state line n
    local -a lines
    for ((idx = 0; idx < visible; idx++)); do
        num="[$((idx + 1))]"
        ((idx >= 9)) && num="   "
        header="${num} ${SESSION_LABELS[$idx]}"
        if [[ $idx -eq $SELECTED_INDEX ]]; then
            printf '\n%s' "${REVERSE}${header}${eol}${NC}"
        else
            printf '\n%s' "${BOLD}${header}${NC}${eol}"
        fi

        lines=()
        if [[ -n "${SESSION_TAILS[$idx]+set}" ]]; then
            # Already wrapped to the width when it was read.
            mapfile -t lines <<<"${SESSION_TAILS[$idx]}"
        else
            state="${SESSION_STATES[$idx]:-}"
            case "$state" in
                # Not loaded: the terminal grew after the last load. Wait for
                # the next refresh instead of showing the pane's bottom.
                "") lines=() ;;
                "$STATE_DORMANT") lines=("(dormant — r in list view to resume)") ;;
                "$STATE_DEAD") lines=("(dead — directory is gone)") ;;
                "$STATE_LOST") lines=("(lost — transcript is gone)") ;;
                *)
                    mapfile -t lines < <(capture_tail_lines "${SESSION_IDS[$idx]}" "$output_lines")
                    for n in "${!lines[@]}"; do
                        line="${lines[$n]}"
                        lines[n]="${line:0:$((term_width - 2))}"
                    done
                    ;;
            esac
        fi
        # The last output_lines of it, padded out to the block's height.
        local first=$((${#lines[@]} - output_lines))
        ((first < 0)) && first=0
        n=0
        # Replies in normal weight, the user's prompts in bold, so who said
        # what reads at a glance; the pane fallback stays dim.
        local style=""
        [[ -n "${SESSION_TAILS[$idx]+set}" ]] || style="$DIM"
        for line in "${lines[@]:$first}"; do
            if [[ -z "$style" && "$line" == "❯ "* ]]; then
                printf '\n%s' "  ${BOLD}${line}${NC}${eol}"
            else
                printf '\n%s' "  ${style}${line}${NC}${eol}"
            fi
            n=$((n + 1))
        done
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
    term_height=$(_term_lines)
    term_width=$(_term_cols)
    frame=$(build_tail_frame "$term_height" "$term_width")
    clear_eos=$(tput ed 2>/dev/null || printf '\033[J')
    # %s, not %b: the frame carries conversation text, and %b would turn a
    # backslash in it ("\n" in a code sample) into a control character.
    printf '\033[?25l\033[H%s%s\033[?25h' "$frame" "$clear_eos"
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
            SELECTED_ID="$current"
            return 0
        fi
    done
    return 0
}

# Return to list view with selected session
return_to_list_view() {
    local selected_id="$1"
    [[ -n "$selected_id" ]] && set_nav_selected "$selected_id"
    cleanup
    # Detach the outer client onto the Navigator; this window closes when we
    # exit. An attach from inside this pane would nest the Navigator (#37).
    view_return_to_navigator
    exit 0
}

# Quit navigator - return to caller session (same handoff as tile.sh)
quit_navigator() {
    cleanup
    # Hand the outer client to the caller (detach -E), then let this window
    # close. Never attach from inside this pane — see view_quit_navigator.
    view_quit_navigator
    exit 0
}

handle_key() {
    local key="$1"
    local count=${#SESSION_IDS[@]}

    case "$key" in
        j | $'\x1b[B')
            if ((count > 0)); then SELECTED_INDEX=$(((SELECTED_INDEX + 1) % count)); fi; SELECTED_ID="${SESSION_IDS[$SELECTED_INDEX]:-}"
            ;;
        k | $'\x1b[A')
            if ((count > 0)); then SELECTED_INDEX=$(((SELECTED_INDEX - 1 + count) % count)); fi; SELECTED_ID="${SESSION_IDS[$SELECTED_INDEX]:-}"
            ;;
        g)
            SELECTED_INDEX=0
            SELECTED_ID="${SESSION_IDS[0]:-}"
            ;;
        G)
            if ((count > 0)); then SELECTED_INDEX=$((count - 1)); fi
            SELECTED_ID="${SESSION_IDS[$SELECTED_INDEX]:-}"
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
    [[ -n "${TAIL_TMP_DIR:-}" ]] && rm -rf "$TAIL_TMP_DIR"
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
    _seed_selection
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
