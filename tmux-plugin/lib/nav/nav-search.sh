#!/usr/bin/env bash
# shellcheck shell=bash
# nav-search.sh - `/` search over the list rows, and n/N between matches.
#
# Owns the search state and the prompt sub-loop. A row matches when the text
# it shows on screen contains the query, case-insensitively — what the user
# can see is what they can find. Project rows match on the project name their
# header shows.
#
# As in vim, `/` is a mode only while the query is typed; after Enter the
# list is back to normal and n/N always mean next/prev match of the last
# query. They never mean anything else, so a stray n with no query does
# nothing but say so. The query stays until a new `/` (empty Enter clears it).

NAV_SEARCH_QUERY=""  # committed query; empty = not searching
NAV_SEARCH_PROMPT=0  # 1 while the `/` prompt is open
NAV_SEARCH_INPUT=""  # text typed so far at the prompt
NAV_SEARCH_MSG=""    # one-shot note for the footer ("no match")
NAV_SEARCH_FOOTER="" # prompt line, filled by _search_footer
NAV_SEARCH_STATUS="" # header note, filled by _search_status
NAV_SEARCH_HIT=-1    # result of _search_find
NAV_SEARCH_MATCHES=() # result of _search_matches

# Does row $1 show text containing $2? Compared lower-cased with the colour
# codes stripped, so a match never depends on how the row is painted.
_search_row_matches() {
    local i="$1" q="${2,,}" text
    [[ -z "$q" ]] && return 1
    _strip_ansi_into "${SESSION_DISPLAYS[$i]:-}"
    text="${NAV_STRIPPED//$SPIN_PLACEHOLDER/}"
    [[ "${text,,}" == *"$q"* ]]
}

# Indices of every row matching $1, in list order, into NAV_SEARCH_MATCHES.
_search_matches() {
    local q="$1" i
    NAV_SEARCH_MATCHES=()
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        _search_row_matches "$i" "$q" && NAV_SEARCH_MATCHES+=("$i")
    done
    return 0
}

# Find the next ("next") or previous ("prev") row matching $1, starting just
# past row $2 and wrapping, so the row under the cursor is found last. Sets
# NAV_SEARCH_HIT to the index, or -1 when nothing matches.
_search_find() {
    local q="$1" from="$2" dir="${3:-next}"
    local n=${#SESSION_IDS[@]} step=1 k i
    NAV_SEARCH_HIT=-1
    ((n == 0)) && return 1
    [[ "$dir" == "prev" ]] && step=-1
    for ((k = 1; k <= n; k++)); do
        i=$(((from + step * k) % n))
        ((i < 0)) && i=$((i + n))
        if _search_row_matches "$i" "$q"; then
            NAV_SEARCH_HIT=$i
            return 0
        fi
    done
    return 1
}

# Put the cursor on row $1: the selection file and the view pane follow, as
# with j/k. Publishes the index in NAV_NEW_INDEX.
_search_jump() {
    local i="$1"
    NAV_NEW_INDEX="$i"
    [[ -n "${SESSION_IDS[$i]:-}" ]] || return 0
    [[ "$(get_nav_selected)" == "${SESSION_IDS[$i]}" ]] && return 0
    set_nav_selected "${SESSION_IDS[$i]}"
    signal_view_update_async
}

# n / N. $1 = "next" or "prev", $2 = current index.
search_step() {
    local dir="$1" cur="$2"
    NAV_NEW_INDEX="$cur"
    if [[ -z "$NAV_SEARCH_QUERY" ]]; then
        NAV_SEARCH_MSG="no previous search"
    elif _search_find "$NAV_SEARCH_QUERY" "$cur" "$dir"; then
        _search_jump "$NAV_SEARCH_HIT"
    else
        NAV_SEARCH_MSG="no match"
    fi
}

# The `/` prompt. Runs its own read loop so the list keeps redrawing under
# it; the cursor follows the first match as the query is typed. Enter keeps
# the query (empty Enter clears it), Esc puts the cursor back where it was.
# $1 = index the search starts from. Leaves the final index in NAV_NEW_INDEX.
search_prompt() {
    local origin="$1" cur="$1" key="" rc=0
    NAV_SEARCH_PROMPT=1
    NAV_SEARCH_INPUT=""
    NAV_SEARCH_MSG=""
    while true; do
        render_list "$cur"
        rc=0
        nav_read_key key "$TICK_INTERVAL" || rc=$?
        [[ $rc -eq 2 ]] && exit 0
        if [[ $rc -ne 0 ]]; then
            SPIN_TICK=$(((SPIN_TICK + 1) % 1000000))
            _flush_pending_view_signal
            continue
        fi
        case "$key" in
            '') # Enter
                NAV_SEARCH_QUERY="$NAV_SEARCH_INPUT"
                [[ -n "$NAV_SEARCH_QUERY" ]] && ! _search_row_matches "$cur" "$NAV_SEARCH_QUERY" &&
                    NAV_SEARCH_MSG="no match"
                break
                ;;
            $'\x1b')
                # A lone Esc cancels; an arrow or other sequence is drained
                # whole and ignored so it cannot leak into the query.
                nav_read_escape
                [[ -n "$NAV_ESC_SEQ" ]] && continue
                cur="$origin"
                _search_jump "$origin"
                break
                ;;
            $'\x7f' | $'\b')
                if [[ -z "$NAV_SEARCH_INPUT" ]]; then
                    cur="$origin"
                    _search_jump "$origin"
                    break
                fi
                NAV_SEARCH_INPUT="${NAV_SEARCH_INPUT%?}"
                ;;
            $'\x15') # Ctrl-U
                NAV_SEARCH_INPUT=""
                ;;
            [[:cntrl:]]) continue ;;
            *) NAV_SEARCH_INPUT+="$key" ;;
        esac
        # Incremental: follow the first match after the starting row, or sit
        # back on the starting row while nothing matches.
        if [[ -n "$NAV_SEARCH_INPUT" ]] && _search_find "$NAV_SEARCH_INPUT" "$origin" next; then
            cur=$NAV_SEARCH_HIT
        else
            cur="$origin"
        fi
        _search_jump "$cur"
    done
    NAV_SEARCH_PROMPT=0
    NAV_SEARCH_INPUT=""
    NAV_NEW_INDEX="$cur"
}

# The prompt line that replaces the footer while `/` is open, into
# NAV_SEARCH_FOOTER. Returns 1 when the prompt is closed, so the renderer
# keeps its key list.
_search_footer() {
    local q
    NAV_SEARCH_FOOTER=""
    [[ $NAV_SEARCH_PROMPT -eq 1 ]] || return 1
    q=$(truncate_display "$NAV_SEARCH_INPUT" 50)
    NAV_SEARCH_FOOTER="/${q}▏  ↵:ok esc:cancel"
    return 0
}

# The search note shown on the header line, into NAV_SEARCH_STATUS: the
# active query and where the cursor is among its matches ("/log [2/5]"), or
# a one-shot message. Returns 1 when there is nothing to show. $1 = selected
# index.
_search_status() {
    local sel="$1" q pos="" k
    NAV_SEARCH_STATUS=""
    [[ $NAV_SEARCH_PROMPT -eq 1 ]] && return 1
    if [[ -z "$NAV_SEARCH_QUERY" ]]; then
        [[ -n "$NAV_SEARCH_MSG" ]] || return 1
        NAV_SEARCH_STATUS="$NAV_SEARCH_MSG"
        return 0
    fi
    q=$(truncate_display "$NAV_SEARCH_QUERY" 30)
    _search_matches "$NAV_SEARCH_QUERY"
    if [[ ${#NAV_SEARCH_MATCHES[@]} -eq 0 ]]; then
        pos="[no match]"
    else
        pos="[-/${#NAV_SEARCH_MATCHES[@]}]"
        for k in "${!NAV_SEARCH_MATCHES[@]}"; do
            if [[ "${NAV_SEARCH_MATCHES[$k]}" -eq "$sel" ]]; then
                pos="[$((k + 1))/${#NAV_SEARCH_MATCHES[@]}]"
                break
            fi
        done
    fi
    [[ -n "$NAV_SEARCH_MSG" ]] && pos="[$NAV_SEARCH_MSG]"
    NAV_SEARCH_STATUS="/${q} ${pos}"
    return 0
}
