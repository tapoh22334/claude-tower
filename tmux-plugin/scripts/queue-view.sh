#!/usr/bin/env bash
# queue-view.sh - Queue view for claude-tower Navigator
# Every Claude session that is waiting on you, the most recent wait on top:
# the session that just stopped is the one whose context is still in your
# head. Visualization only — pick a row to jump to that session and answer
# it yourself.
#
# Runs IN the Navigator's list pane, as a display mode of that pane: the list
# loop execs this script in the foreground and takes the screen back when it
# exits. It never creates tmux windows or attaches clients. Moving the cursor
# writes the shared selection, so the right-hand view pane follows the row
# under the cursor exactly as it does in list mode. (The earlier design made
# this a window inside a real tower_* session and attached from inside that
# pane on the way back, which nested the Navigator inside itself — #37.)
#
# Exit codes tell the list loop what to do next:
#   0  back to list mode (selection already written)
#   3  the user pressed q: quit the Navigator
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
# shellcheck source=../lib/queue.sh
source "$SCRIPT_DIR/../lib/queue.sh"

REFRESH_INTERVAL="${TOWER_QUEUE_REFRESH:-2}"
# How often the key loop checks a running reload for its result.
readonly RELOAD_POLL=0.1
readonly QUEUE_EXIT_QUIT=3

readonly NC=$'\033[0m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly REVERSE=$'\033[7m'
readonly CYAN=$'\033[36m'
# Project column. Not cyan: that is the question kind's color.
readonly PROJECT_FG=$'\033[35m'
# Attribute-off codes. A row's parts are dimmed or colored with these
# instead of a full reset, which would also end the selected row's reverse
# video halfway along the row.
readonly UNDIM=$'\033[22m'
readonly DEFAULT_FG=$'\033[39m'

readonly Q_MAX_WIDTH="${TOWER_LIST_MAX_WIDTH:-80}"
readonly Q_AGE_COL=6
# The project column grows to its longest name, up to this many cells.
readonly Q_PROJECT_MAX=16
readonly Q_KEYS="j/k move  1-9 open  Enter list  q quit"

# State: parallel arrays, already ordered (most recent wait first).
QUEUE_IDS=()
QUEUE_KINDS=()
QUEUE_AGES=()
QUEUE_PROJECTS=()
SELECTED_INDEX=0
# Composed rows, built once per load (and again only if the width changes):
# a label reads its session's transcript, so composing on every j/k redraw
# made each keypress cost one transcript scan per row (#86).
QUEUE_LABELS=()
QUEUE_ROWS=()
QUEUE_ROWS_WIDTH=""

# Fill the arrays from collect_queue (lib/queue.sh), synchronously: the
# first frame. Later reloads run in the background (queue_reload_tick).
load_queue() {
    local previous_id="${QUEUE_IDS[$SELECTED_INDEX]-}"
    _fill_queue < <(collect_queue)
    _place_cursor "$previous_id"
}

# The arrays from collect_queue's lines on stdin; rows not composed yet.
_fill_queue() {
    QUEUE_IDS=()
    QUEUE_KINDS=()
    QUEUE_AGES=()
    QUEUE_PROJECTS=()
    QUEUE_LABELS=()
    QUEUE_ROWS=()
    QUEUE_ROWS_WIDTH=""

    local since session_id kind project label reltime
    while IFS=$'\t' read -r since session_id kind project label; do
        [[ -z "$session_id" ]] && continue
        QUEUE_IDS+=("$session_id")
        QUEUE_KINDS+=("$kind")
        QUEUE_PROJECTS+=("$project")
        QUEUE_LABELS+=("$label")
        # "5d ago" -> "5d": the queue's age column is tight and every row
        # is an age, so the " ago" suffix is redundant noise.
        # since 0 = no activity time known (no transcript): an age counted
        # from the epoch ("20760d") would be a lie.
        if [[ "$since" =~ ^[1-9][0-9]*$ ]]; then
            reltime=$(format_relative_time "$since")
            QUEUE_AGES+=("${reltime% ago}")
        else
            QUEUE_AGES+=("?")
        fi
    done
    return 0
}

# Everything a reload produces, written into directory $1 by the
# background job: the entries with their ages, and the rows composed at
# the width of the moment. Formatting forks once or twice per row; done
# here, it costs the key loop nothing (#110).
_queue_snapshot() {
    local dir="$1" idx
    collect_queue >"$dir/queue"
    _fill_queue <"$dir/queue"
    _compose_queue_rows
    for ((idx = 0; idx < ${#QUEUE_IDS[@]}; idx++)); do
        printf '%s\t%s\t%s\t%s\t%s\n' "${QUEUE_IDS[$idx]}" "${QUEUE_KINDS[$idx]}" \
            "${QUEUE_PROJECTS[$idx]}" "${QUEUE_AGES[$idx]}" "${QUEUE_LABELS[$idx]}"
    done >"$dir/entries"
    printf '%s\n' "${QUEUE_ROWS[@]}" >"$dir/rows"
    printf '%s\n' "$QUEUE_ROWS_WIDTH" >"$dir/width"
}

# A snapshot directory into the arrays, without forking: this runs in the
# key loop. Rows composed for another width are dropped and recomposed on
# the next frame.
_apply_queue_snapshot() {
    local dir="$1" previous_id="${QUEUE_IDS[$SELECTED_INDEX]-}"
    local session_id kind project age label width=""
    QUEUE_IDS=()
    QUEUE_KINDS=()
    QUEUE_AGES=()
    QUEUE_PROJECTS=()
    QUEUE_LABELS=()
    QUEUE_ROWS=()
    QUEUE_ROWS_WIDTH=""
    while IFS=$'\t' read -r session_id kind project age label; do
        [[ -z "$session_id" ]] && continue
        QUEUE_IDS+=("$session_id")
        QUEUE_KINDS+=("$kind")
        QUEUE_PROJECTS+=("$project")
        QUEUE_AGES+=("$age")
        QUEUE_LABELS+=("$label")
    done <"$dir/entries"
    if ((${#QUEUE_IDS[@]} > 0)); then
        mapfile -t QUEUE_ROWS <"$dir/rows"
        IFS= read -r width <"$dir/width" || true
        QUEUE_ROWS_WIDTH="$width"
    fi
    _place_cursor "$previous_id"
}

# The cursor stays on the same session, not the same row number: newest
# waits enter at the top, so every reload that brings a new one shifts the
# rows under the cursor. Kept by row number, the highlight would land on a
# different session than the view pane shows, and Enter would hand the list
# that one. When the session left the queue, the cursor stays at its row and
# the view pane is moved to whatever is there now.
_place_cursor() {
    local previous_id="$1"
    local count=${#QUEUE_IDS[@]} i
    if [[ -n "$previous_id" ]]; then
        for ((i = 0; i < count; i++)); do
            if [[ "${QUEUE_IDS[$i]}" == "$previous_id" ]]; then
                SELECTED_INDEX=$i
                return 0
            fi
        done
    fi
    if [[ $count -eq 0 ]]; then
        SELECTED_INDEX=0
    elif [[ $SELECTED_INDEX -ge $count ]]; then
        SELECTED_INDEX=$((count - 1))
    fi
    [[ -n "$previous_id" ]] && _follow_selection
    return 0
}

# Rows are composed to this width: the pane, capped at Q_MAX_WIDTH. Never
# wider than the pane: the frame fills the screen to its last line, so one
# row that wraps scrolls the whole frame on every redraw. (The list pane is
# 30% of the terminal, under 50 columns on anything narrower than 166.)
_content_width() {
    local w
    w=$(_term_cols)
    ((w > Q_MAX_WIDTH)) && w=$Q_MAX_WIDTH
    ((w < 20)) && w=20
    echo "$w"
}

# $1 cut to at most $2 cells as str_display_width measures it. A cut string
# ends in "…", which truncate_display counts as one cell and
# str_display_width as two (#92); cut one cell shorter so the column holds
# under either count.
_fit() {
    local s="$1" max="$2"
    if (($(str_display_width "$s") <= max)); then
        printf '%s\n' "$s"
    else
        truncate_display "$s" "$((max - 1))"
    fi
}

# Compose one queue row:
#   " 1 ⚠ claude-tower  queue の並びを逆に…        2m"
# number (the 1-9 key that opens it; blank past 9), the wait icon in its
# kind's color, the project padded to a shared column, the title truncated
# to what is left, and the age right-aligned in a fixed column. Widths are
# display cells. Colors end with attribute-off codes, never a full reset,
# so the selected row's reverse video runs the whole width.
# $1 index (0-based) $2 kind $3 project $4 label $5 age
# $6 project column width $7 content width (both optional)
_queue_row() {
    local idx="$1" kind="$2" project="$3" label="$4" age="$5"
    local project_w="${6:-12}" width="${7-}"
    [[ -n "$width" ]] || width=$(_content_width)

    # Past 9 there is no key; a dot says "no number" where a blank looked
    # like a rendering fault.
    # Padded here, not by printf: %2s counts bytes, and "·" is two of them.
    local num=" ·"
    ((idx < 9)) && num=" $((idx + 1))"
    local icon icon_w
    icon=$(_wait_icon "$kind")
    icon_w=$(str_display_width "$icon")

    # A pane too narrow for the project column drops it.
    local pw=0 ppad="" psep=""
    if ((project_w > 0)); then
        project=$(_fit "$project" "$project_w")
        pw=$(str_display_width "$project")
        printf -v ppad '%*s' "$((project_w - pw))" ''
        psep="  "
    else
        project=""
    fi

    # " N " + icon + " " + project column + "  "
    local left=$((3 + icon_w + 1 + project_w + ${#psep}))
    # -1: at least one space between the title and the age.
    local budget=$((width - left - Q_AGE_COL - 1))
    ((budget < 1)) && budget=1
    label=$(_fit "$label" "$budget")
    local label_w pad_w pad age_w gap rpad
    label_w=$(str_display_width "$label")
    pad_w=$((width - left - label_w - Q_AGE_COL))
    ((pad_w < 1)) && pad_w=1
    printf -v pad '%*s' "$pad_w" ''
    age_w=$(str_display_width "$age")
    gap=$((Q_AGE_COL - age_w))
    ((gap < 0)) && gap=0
    printf -v rpad '%*s' "$gap" ''

    printf '%s%s%s %s%s%s %s%s%s%s%s%s%s%s%s%s' \
        "$DIM" "$num" "$UNDIM" \
        "$(_wait_color "$kind")" "$icon" "$DEFAULT_FG" \
        "$PROJECT_FG" "$project" "$DEFAULT_FG" "$ppad" "$psep" \
        "$label" "$pad" "$rpad" "$DIM$age" "$UNDIM"
}

# Width of the project column: the longest project name, capped, and
# narrowed so the title keeps at least 12 cells in a $1-wide row. 0 (no
# column) when the row has no room for even 6 cells of project.
_project_col_width() {
    local width="$1" p w max=4
    for p in "${QUEUE_PROJECTS[@]}"; do
        w=$(str_display_width "$p")
        ((w > max)) && max=$w
    done
    ((max > Q_PROJECT_MAX)) && max=$Q_PROJECT_MAX
    # number + icon + spaces + age, then the title's 12
    local room=$((width - 6 - 2 - Q_AGE_COL - 12))
    if ((room < 6)); then
        echo 0
        return 0
    fi
    ((max > room)) && max=$room
    echo "$max"
}

# Full frame on stdout, exactly $1 lines: the title, a blank line, the rows,
# blank fill, and the key help pinned to the bottom line. The last line has
# no trailing newline (a full-height frame with one scrolls every redraw —
# the list-view endless-scroll class).
build_queue_frame() {
    local term_height="$1" term_width="$2"
    local eol=$'\033[K'
    local count=${#QUEUE_IDS[@]}

    printf '%s' "${BOLD}${CYAN}Queue${NC}"
    if ((count > 0)); then
        printf '%s' "  ${DIM}${count} waiting${NC}"
    fi
    printf '%s' "$eol"

    # Lines between the title block (2) and the key help (1).
    local avail=$((term_height - 3))
    ((avail < 1)) && avail=1
    local used=0

    printf '\n%s' "$eol"
    if [[ $count -eq 0 ]]; then
        printf '\n%s' " ${DIM}Nothing waiting — all caught up.${NC}${eol}"
        used=1
    else
        # Cap to the rows that fit, collapse the rest.
        local shown=$count
        if ((count > avail)); then shown=$((avail - 1)); fi
        ((shown < 1)) && shown=1

        # Normally already composed by render_frame; composing here keeps the
        # frame correct when called on its own (the result is not kept — this
        # runs under $(...)).
        _compose_queue_rows

        local idx row
        for ((idx = 0; idx < shown; idx++)); do
            row="${QUEUE_ROWS[$idx]}"
            if [[ $idx -eq $SELECTED_INDEX ]]; then
                printf '\n%s' "${REVERSE}${row}${eol}${NC}"
            else
                printf '\n%s' "${row}${NC}${eol}"
            fi
        done
        used=$shown
        if ((shown < count)); then
            printf '\n%s' "   ${DIM}… +$((count - shown)) more${NC}${eol}"
            used=$((used + 1))
        fi
    fi

    while ((used < avail)); do
        printf '\n%s' "$eol"
        used=$((used + 1))
    done
    printf '\n%s' " ${DIM}$(truncate_display "$Q_KEYS" "$((term_width - 2))")${NC}${eol}"
}

# Fill QUEUE_ROWS for the current width, unless it already is. Call it bare,
# not under $(...): the arrays it fills would be discarded with the subshell.
_compose_queue_rows() {
    local width idx label project_w
    width=$(_content_width)
    if [[ "$QUEUE_ROWS_WIDTH" == "$width" && ${#QUEUE_ROWS[@]} -eq ${#QUEUE_IDS[@]} ]]; then
        return 0
    fi
    project_w=$(_project_col_width "$width")
    QUEUE_ROWS=()
    for ((idx = 0; idx < ${#QUEUE_IDS[@]}; idx++)); do
        label="${QUEUE_LABELS[$idx]-}"
        [[ -n "${QUEUE_LABELS[$idx]+set}" ]] || label=$(queue_label "${QUEUE_IDS[$idx]}")
        QUEUE_ROWS+=("$(_queue_row "$idx" "${QUEUE_KINDS[$idx]}" "${QUEUE_PROJECTS[$idx]:--}" \
            "$label" "${QUEUE_AGES[$idx]}" "$project_w" "$width")")
    done
    QUEUE_ROWS_WIDTH="$width"
}

# One reload step, called on every pass of the key loop. Starts a reload in
# the background when none runs; when one has finished, applies it and
# returns 0 so the caller redraws. Returns 1 otherwise: the frame on screen
# is still current, and keys keep moving the cursor on it meanwhile (#110).

queue_reload_tick() {
    if [[ -z "$BG_LOAD_PID" ]]; then
        bg_load_start _queue_snapshot
        return 1
    fi
    bg_load_done || return 1
    # shellcheck disable=SC2153  # set by bg_load_start (lib/queue.sh)
    _apply_queue_snapshot "$BG_LOAD_DIR"
    bg_load_discard
    return 0
}

render_frame() {
    local term_height term_width frame clear_eos
    _compose_queue_rows
    term_height=$(_term_lines)
    term_width=$(_term_cols)
    frame=$(build_queue_frame "$term_height" "$term_width")
    clear_eos=$(tput ed 2>/dev/null || printf '\033[J')
    # %s, not %b: titles are user text, and %b would act on a backslash in
    # one ("C:\code" — \c stops printf, leaving the cursor hidden).
    printf '\033[?25l\033[H%s%s\033[?25h' "$frame" "$clear_eos"
}

# Hand the pane back to the list loop. The selection file is the only thing
# that crosses the boundary: the loop re-reads it to place its cursor.
return_to_list_view() {
    local selected_id="$1"
    [[ -n "$selected_id" ]] && set_nav_selected "$selected_id"
    cleanup
    exit 0
}

# q in the queue means "quit the Navigator", but the queue is not the one to
# do it — it is a mode of the list pane, and the list loop owns the exit
# (it knows the caller session and how to hand the client back). Report it.
quit_navigator() {
    cleanup
    exit "$QUEUE_EXIT_QUIT"
}

# Publish the row under the cursor and point the view pane at it, so the
# right-hand pane shows that session while the user is still deciding. Same
# contract as list mode's j/k: writing the file alone is not enough, because
# the view's nested client is parked inside attach-session and only moves
# when someone redirects it (nav_redirect_view). The redirect runs in the
# background so a j/k burst never waits on tmux; it re-reads the selection
# when it runs, so the last move wins.
_follow_selection() {
    local count=${#QUEUE_IDS[@]}
    ((count > 0)) || return 0
    set_nav_selected "${QUEUE_IDS[$SELECTED_INDEX]}"
    nav_redirect_view >/dev/null 2>&1 &
    # Keep it out of the job table, as _spawn_background_rebuild explains.
    disown "$!" 2>/dev/null || true
}

# Start with the cursor on the session the list had selected, when it is in
# the queue; otherwise on the most recent wait.
_seed_selection() {
    local current i
    current=$(get_nav_selected)
    [[ -n "$current" ]] || return 0
    for ((i = 0; i < ${#QUEUE_IDS[@]}; i++)); do
        if [[ "${QUEUE_IDS[$i]}" == "$current" ]]; then
            SELECTED_INDEX=$i
            return 0
        fi
    done
}

handle_key() {
    local key="$1"
    local count=${#QUEUE_IDS[@]}
    case "$key" in
        j | $'\x1b[B')
            if ((count > 0)); then SELECTED_INDEX=$(((SELECTED_INDEX + 1) % count)); fi
            _follow_selection
            ;;
        k | $'\x1b[A')
            if ((count > 0)); then SELECTED_INDEX=$(((SELECTED_INDEX - 1 + count) % count)); fi
            _follow_selection
            ;;
        g)
            SELECTED_INDEX=0
            _follow_selection
            ;;
        G)
            if ((count > 0)); then SELECTED_INDEX=$((count - 1)); fi
            _follow_selection
            ;;
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
    bg_load_discard
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
    _seed_selection
    render_frame

    local key key2 read_rc wait_for
    while true; do
        key=""
        read_rc=0
        # Idle, wait the refresh interval for a key; while a reload runs,
        # wake often to pick up its result.
        wait_for="$REFRESH_INTERVAL"
        [[ -n "$BG_LOAD_PID" ]] && wait_for="$RELOAD_POLL"
        # nav_read_key guards the orphaned-terminal busy-loop (rc 2 = pane gone).
        nav_read_key key "$wait_for" || read_rc=$?
        [[ $read_rc -eq 2 ]] && exit 0
        if [[ $read_rc -eq 0 ]]; then
            if [[ "$key" == $'\x1b' ]]; then
                read -rsn2 -t 0.1 key2 || true
                [[ -z "${key2:-}" ]] && continue
                key="${key}${key2}"
            fi
            handle_key "$key"
            render_frame
            # A reload that finished meanwhile still lands now, not after
            # the user stops pressing keys.
            [[ -n "$BG_LOAD_PID" ]] && queue_reload_tick && render_frame
        elif queue_reload_tick; then
            render_frame
        fi
    done
}

# Sourcing guard: bats sources this file to unit-test the pure functions.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
