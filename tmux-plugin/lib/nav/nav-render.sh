#!/usr/bin/env bash
# shellcheck shell=bash
# nav-render.sh - Turning the session arrays into the text on screen.
#
# Owns the colors, the width budget, row/header composition and the two
# full-screen draws (render_list, show_help). Nothing here decides *what*
# sessions exist; it only decides how they look.

# ============================================================================
# Configuration
# ============================================================================

# Spinner cadence: while idle the loop wakes every TICK_INTERVAL to advance
# the busy spinner (a pure string-substitution redraw); the session list
# itself is only rebuilt every TICKS_PER_REFRESH ticks (= 2s, the old
# REFRESH_INTERVAL).
readonly TICK_INTERVAL=0.25
readonly TICKS_PER_REFRESH=8
readonly -a SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧')
# Placeholder embedded in busy rows at build time, replaced with the current
# frame at render time so the spinner turns without rebuilding the list.
readonly SPIN_PLACEHOLDER='@@SPIN@@'
SPIN_TICK=0

# Colors for navigator (using $'...' syntax for actual escape sequences)
readonly NAV_C_HEADER=$'\033[1;36m'
readonly NAV_C_SELECTED=$'\033[7m' # Reverse video
readonly NAV_C_NORMAL=$'\033[0m'
readonly NAV_C_DIM=$'\033[2m'
readonly NAV_C_ACCENT=$'\033[1;32m'  # Green bold - for highlights
readonly NAV_C_ERROR=$'\033[1;31m'   # Red bold - for errors
readonly NAV_C_ACTIVE=$'\033[32m'    # Green - active sessions
readonly NAV_C_DORMANT=$'\033[90m'   # Gray - dormant sessions

readonly NAV_C_EXTERNAL=$'\033[36m'  # Cyan - running outside Tower

# Rows and headers render inside this many cells, so a wide terminal does
# not stretch a one-line title across the whole screen. Overridable.
readonly NAV_MAX_WIDTH="${TOWER_LIST_MAX_WIDTH:-80}"
# Floor so a narrow pane still leaves room for a readable label; below this
# the content simply overflows the pane rather than collapsing to nothing.
readonly NAV_MIN_WIDTH="${TOWER_LIST_MIN_WIDTH:-50}"
# Right-hand status column (unread ✱ + subagent ⚙N), fixed so the marks
# line up down the list instead of floating after each title.
readonly NAV_RIGHT_COL=6

# Terminal geometry, in one place.
#
# tput needs a controlling terminal. Without one it answers from $TERM, or not
# at all, and the answer changes between runs — which made rendering tests
# nondeterministic: the same file reported 13, 14, 15 and 16 of a declared 17
# tests across four consecutive runs, tests vanishing rather than failing.
# TOWER_TERM_COLS / TOWER_TERM_LINES let a caller state the size instead of
# asking, which is what the test helper does. Production leaves them unset and
# gets tput as before.
# Effective content width: the terminal, clamped to [MIN, MAX].
# _term_cols/_term_lines live in common.sh — every view needs them.
#
# Cached per pass. Every row asks for this two or three times (label budget,
# row composition, group rule), and each miss forks tput. The terminal cannot
# resize midway through one rebuild, so one reading per pass is enough;
# _reset_width_cache drops it when a new pass starts or the frame redraws.
_NAV_WIDTH_CACHE=""
_reset_width_cache() { _NAV_WIDTH_CACHE=""; }
_content_width() {
    if [[ -n "$_NAV_WIDTH_CACHE" ]]; then
        echo "$_NAV_WIDTH_CACHE"
        return 0
    fi
    local w
    w=$(_term_cols)
    ((w > NAV_MAX_WIDTH)) && w=$NAV_MAX_WIDTH
    ((w < NAV_MIN_WIDTH)) && w=$NAV_MIN_WIDTH
    _NAV_WIDTH_CACHE="$w"
    echo "$w"
}

# Compose a list row: "  <icon> <label><padding><marks>", with marks
# right-aligned into the fixed NAV_RIGHT_COL so they line up down the list.
# $1 icon (may contain ANSI), $2 plain label, $3 marks (may contain ANSI).
# Label width is measured on the plain text; marks width is measured with
# ANSI stripped so color codes don't count toward the column.
_compose_row() {
    local icon="$1" label="$2" marks="$3"
    local width icon_w label_w marks_plain marks_w pad_w pad=""
    width=$(_content_width)

    # Fixed left overhead: 2-space indent (added by the renderer) + the
    # state icon's own display width + one separating space. Measured, not
    # assumed: some state glyphs (●, ◇) are two cells wide.
    icon_w=$(str_display_width "$(_strip_ansi_str "$icon")")
    local left=$((2 + icon_w + 1))

    # Hard cap the label to the row budget. _session_label already sizes to
    # this, but defend the invariant here too so no caller overflows the row.
    local budget=$((width - left - NAV_RIGHT_COL))
    ((budget < 10)) && budget=10
    label=$(truncate_display "$label" "$budget")

    label_w=$(str_display_width "$label")
    marks_plain=$(_strip_ansi_str "$marks")
    marks_w=$(str_display_width "$marks_plain")

    # Pad the label out so the marks sit in the fixed right column.
    pad_w=$((width - left - label_w - NAV_RIGHT_COL))
    ((pad_w < 1)) && pad_w=1
    printf -v pad '%*s' "$pad_w" ''

    if [[ -n "$marks" ]]; then
        local gap=$((NAV_RIGHT_COL - marks_w))
        ((gap < 0)) && gap=0
        local rpad=""
        printf -v rpad '%*s' "$gap" ''
        printf '%s %s%s%s%s\n' "$icon" "$label" "$pad" "$rpad" "$marks"
    else
        printf '%s %s\n' "$icon" "$label"
    fi
}

# Strip ANSI CSI sequences (color, cursor) so display width can be measured.
# Filter form, kept for callers that pipe into it.
strip_ansi_seq() {
    sed -E $'s/\033\\[[0-9;?]*[a-zA-Z]//g'
}

# Same thing for a single string, without the sed. Every row composed calls
# this twice, and `$(printf ... | strip_ansi_seq)` costs a subshell plus a
# fork+exec each time — measurable once the list is more than a few rows.
_strip_ansi_str() {
    local s="$1" out="" rest
    while [[ "$s" == *$'\033['* ]]; do
        out+="${s%%$'\033['*}"
        rest="${s#*$'\033['}"
        # A CSI sequence ends at its first letter; drop through it.
        while [[ -n "$rest" && "$rest" != [a-zA-Z]* ]]; do rest="${rest:1}"; done
        s="${rest:1}"
    done
    printf '%s' "$out$s"
}

# The group header row text for project dir $1 with $2 unmanaged claude
# processes. The project name is the one thing that must be findable at a
# glance, so it gets the strongest treatment on screen: bold cyan against dim
# rows, with a rule running out to the capped content width (not the raw
# terminal, so a wide screen doesn't draw a rule clear across the display).
_compose_group_header() {
    local d="$1" extern="${2:-0}"
    local dname header rule_w
    # basename without the fork. Strip a trailing slash, then everything up
    # to the last one; "/" has nothing left, so keep it as itself.
    dname="${d:-unknown}"
    dname="${dname%/}"
    dname="${dname##*/}"
    [[ -z "$dname" ]] && dname="/"
    header="${NAV_C_HEADER}${dname}${NAV_C_NORMAL}"
    if ((extern > 0)); then
        # Live claude processes here that Tower doesn't manage
        # (forks / sessions started in plain terminals).
        header+=" ${NAV_C_EXTERNAL}⚡${extern}${NAV_C_NORMAL}"
    fi
    rule_w=$(( $(_content_width) - $(str_display_width "$dname") - 4 ))
    if ((extern > 0)); then rule_w=$((rule_w - 3)); fi
    if ((rule_w > 0)); then
        local rule="" k
        for ((k = 0; k < rule_w; k++)); do rule+="─"; done
        header+=" ${NAV_C_DIM}${rule}${NAV_C_NORMAL}"
    fi
    printf '%s' "$header"
}

# Rendering
# ============================================================================

# Render session list (double-buffered to prevent flicker)
render_list() {
    local selected_index="$1"
    local term_height
    # Re-read the terminal size every frame, and drop the cached width with
    # it, so a resize is picked up on the next redraw rather than at the next
    # rebuild (which can be seconds away).
    _reset_width_cache
    term_height=$(_term_lines)
    # Row budget for the body (session rows + group headers + separator).
    # Reserve: header (2) + footer (2). If the frame is even one line
    # taller than the terminal, every redraw scrolls the screen and the
    # refresh loop turns into an endless upward crawl.
    local max_lines=$((term_height - 4))
    [[ $max_lines -lt 1 ]] && max_lines=1

    # Build output in variable first (double buffering)
    local output=""

    # Get current focus state
    local focus
    focus=$(get_nav_focus)

    # Focus indicator
    local focus_indicator=""
    if [[ "$focus" == "list" ]]; then
        focus_indicator="${NAV_C_ACCENT}[ACTIVE]${NAV_C_NORMAL}"
    else
        focus_indicator="${NAV_C_DIM}[─────]${NAV_C_NORMAL}"
    fi

    # Every line ends with \033[K (clear-to-end-of-line) before the newline.
    # Without it, a row left over from a longer previous render (e.g. the
    # multi-line help screen) keeps its old trailing characters when this
    # frame's line is shorter or blank — writing "\n" alone only moves the
    # cursor down, it does not erase what was already on that row. The
    # trailing `tput ed` below only clears rows *after* the last line we
    # print, so it can't fix a stale row sitting in the middle of the screen.
    local eol=$'\033[K'

    # Header with focus indicator
    output+="${NAV_C_HEADER}Sessions${NAV_C_NORMAL} ${focus_indicator}${eol}\n"
    output+="${eol}\n"

    if [[ ${#SESSION_IDS[@]} -eq 0 ]]; then
        output+="${NAV_C_DIM}(no sessions)${NAV_C_NORMAL}${eol}\n"
    else
        # Compose body lines first (group headers, separator, session rows)
        # so the height budget and "+N more" stay exact with headers in
        # the mix. body_idx maps each line to its session index (-1 = not
        # a session row).
        local spin_frame="${SPINNER_FRAMES[$((SPIN_TICK % ${#SPINNER_FRAMES[@]}))]}"
        local -a body_lines=() body_idx=()
        local i display
        for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
            if [[ $BROKEN_START -ge 0 && $i -eq $BROKEN_START ]]; then
                body_lines+=("${NAV_C_DIM}── unrecoverable ──${NAV_C_NORMAL}")
                body_idx+=(-1)
            fi
            if [[ -n "${SESSION_HEADERS[$i]:-}" ]]; then
                body_lines+=("${SESSION_HEADERS[$i]}")
                body_idx+=(-1)
            fi
            display="${SESSION_DISPLAYS[$i]//$SPIN_PLACEHOLDER/$spin_frame}"
            if [[ $i -eq $selected_index ]]; then
                body_lines+=("${NAV_C_SELECTED}  ${display} ${NAV_C_NORMAL}")
            else
                body_lines+=("  ${display}")
            fi
            body_idx+=("$i")
        done

        local total=${#body_lines[@]}
        local shown=$total
        if [[ $total -gt $max_lines ]]; then
            shown=$((max_lines - 1))   # keep one row for "+N more"
            [[ $shown -lt 1 ]] && shown=1
        fi
        local n
        for ((n = 0; n < shown; n++)); do
            output+="${body_lines[$n]}${eol}\n"
        done
        if [[ $shown -lt $total ]]; then
            # Count hidden *sessions*, not hidden lines
            local hidden=0
            for ((n = shown; n < total; n++)); do
                if [[ "${body_idx[$n]}" -ge 0 ]]; then hidden=$((hidden + 1)); fi
            done
            output+="${NAV_C_DIM}... +${hidden} more${NAV_C_NORMAL}${eol}\n"
        fi
    fi

    # Footer with keybindings (compact). No trailing \n on the last line:
    # if the frame fills the terminal exactly, a final newline would still
    # scroll the screen by one row on every redraw.
    output+="${eol}\n"
    # Keep this within 80 cells: a longer footer wraps and the trailing
    # binding is lost on an 80-wide capture.
    output+="${NAV_C_DIM}j/k:nav ↵/i:input n:add f:fork N:newdir D:del r:resume t:tail w:queue q:quit${NAV_C_NORMAL}${eol}"

    # Clear to end of screen code
    local clear_eos
    clear_eos=$(tput ed 2>/dev/null || printf '\033[J')

    # Single atomic write: hide cursor, move home, print, clear rest.
    # Cursor stays HIDDEN — the selection is the reverse-video row, so a
    # terminal cursor is never needed and, left visible, parks as a stray
    # block on the last line. The EXIT trap restores it; interactive
    # sub-flows (fzf, y/n) re-enable it themselves after their own clear.
    printf '\033[?25l\033[H%b%s' "$output" "$clear_eos"
}

# Show help screen
show_help() {
    clear
    echo -e "${NAV_C_HEADER}Navigator Help${NAV_C_NORMAL}"
    echo ""
    echo "  Navigation:"
    echo "    j / ↓      Move down"
    echo "    k / ↑      Move up"
    echo "    g          Go to first session"
    echo "    G          Go to last session"
    echo ""
    echo "  Actions:"
    echo "    Enter / i  Focus view pane (input mode)"
    echo "    n          Add session (pick existing Claude session or start new)"
    echo "    f          Fork: new session in the selected session's directory"
    echo "    N          New session in a picked project directory"
    echo "    D          Delete from Tower (Claude's transcript is kept)"
    echo "    r          Resume selected dormant session"
    echo "    Tab / t    Tile view / Tail view (live output)"
    echo "    w          Queue view (sessions waiting on you)"
    echo "    ?          Show this help      q  Quit Navigator"
    echo ""
    # Keep the help under 24 rows total: at 24 printed lines the final
    # newline scrolls the title off a default-size terminal.
    echo "  States:    ${SPINNER_FRAMES[0]} working  ✱ new output  ▶ waiting  ○ dormant  ◇ external  ✗/? gone"
    echo "  Marks:     ⚙N active subagents (right)   ⚡N unmanaged claude in dir (header)"
    echo ""
    echo -e "${NAV_C_DIM}Press any key to continue...${NAV_C_NORMAL}"
    read -rsn1
}
