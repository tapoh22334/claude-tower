#!/usr/bin/env bash
# Navigator list: r starts dormant sessions without leaving the list
# (value/004-nav-r-start). Sourced by navigator-list.sh; uses the list
# arrays (nav-build.sh), the optimistic row edits (nav-optimistic.sh) and
# _nav_hint (nav-actions.sh).
#
# r means one thing on every row: start the dormant sessions under the
# cursor. Under a session row that is the session itself; under a project
# row it is every session listed in that project. Enter also resumes a
# dormant row, but then moves the focus into it — r is for waking several
# in a row while the focus stays in the list.

# Can r start a session in display state $1? The same test Enter's resume
# applies (open_selected): no tmux session, registered, not running
# elsewhere, and its transcript and directory still there — which is what
# "dormant" means. A • row (dormant with unread output) is dormant too.
_state_is_startable() {
    [[ "$1" == dormant ]]
}

# Why r cannot start a session in display state $1, as one line for under
# the list. Takes the state, not the id: get_display_state is the costly
# part, so the caller asks it once.
_unstartable_reason() {
    case "$1" in
        external) echo "Running outside Tower (◇) — use its own terminal" ;;
        dead) echo "Its directory is gone (✗) — it cannot be resumed" ;;
        lost) echo "Its transcript is gone (?) — it cannot be resumed" ;;
        '') echo "Not registered — press a to add" ;;
        *) echo "Already running" ;;
    esac
}

# Dormant sessions listed under project dir $1, one id per line, in list
# order.
_startable_in_project() {
    local d="$1" i id
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        [[ "${SESSION_DIRS[$i]}" == "$d" ]] || continue
        id="${SESSION_IDS[$i]}"
        _row_is_project "$id" && continue
        _state_is_startable "$(get_display_state "$id")" && printf '%s\n' "$id"
    done
    return 0
}

# Start session $1 and draw its row as ◐. Call it bare, never under $(...):
# the row edit lives in the list arrays. 0 started, 1 failed; on failure
# NAV_START_ERR holds the last line restore printed.
NAV_START_ERR=""
_start_one_session() {
    local id="$1" err rc=0
    NAV_START_ERR=""
    err=$(TOWER_QUIET_ERRORS=1 "$SCRIPT_DIR/session-restore.sh" "$id" \
        2>&1 >/dev/null </dev/null) || rc=$?
    if ((rc != 0)); then
        [[ -n "$err" ]] && printf '%s\n' "$err" >&2
        err=$(_strip_ansi_str "$(grep -v '^[[:space:]]*$' <<<"$err" | tail -n 1)")
        NAV_START_ERR="${err#Error: }"
        return 1
    fi
    _mark_session_starting "$id" || true
    return 0
}

# r with the cursor on row $1 (the row on screen). Says under the list why
# nothing started, or how many did. NAV_START_COUNT is the number started.
# Call it bare: it edits the list arrays.
#
# The starts run in the key loop, one session-restore.sh after another, so
# the list does not take keys meanwhile. Two things keep that short and
# harmless: the live-process table is taken once for every row asked (it
# costs most of a second per row otherwise), and keys typed during the
# starts are dropped afterwards rather than replayed onto the list.
NAV_START_COUNT=0
start_under_cursor() {
    local shown="${1:-}" selected id dir state index started=0 failed=0
    local -a ids=()
    NAV_START_COUNT=0
    selected=$(get_nav_selected)
    # Starting runs claude, so act only on the row the person sees: a stale
    # list loop can leave the selected file naming another row (as for
    # Enter, value/003-nav-keys deviation 7).
    [[ -n "$shown" && "$shown" == "$selected" ]] || return 0

    local saved_table="$LIVE_PROCS_TABLE" saved_ready="$LIVE_PROCS_READY"
    LIVE_PROCS_TABLE=$(list_live_claude_processes)
    LIVE_PROCS_READY=1

    if _row_is_project "$shown"; then
        dir=$(_row_project_dir "$shown")
        mapfile -t ids < <(_startable_in_project "$dir")
        if ((${#ids[@]} == 0)); then
            _nav_hint "No dormant session in this project"
        else
            _nav_hint "Starting ${#ids[@]} session(s)…"
        fi
    else
        state=$(get_display_state "$shown")
        if _state_is_startable "$state"; then
            ids=("$shown")
        else
            _nav_hint "$(_unstartable_reason "$state")"
        fi
    fi
    LIVE_PROCS_TABLE="$saved_table"
    LIVE_PROCS_READY="$saved_ready"
    ((${#ids[@]} > 0)) || return 0

    for id in "${ids[@]}"; do
        if _start_one_session "$id"; then
            started=$((started + 1))
        else
            failed=$((failed + 1))
        fi
        # Each row turns ◐ as it starts, rather than all at the end.
        ((${#ids[@]} > 1)) && render_list "$(_index_of_row "$shown")"
    done
    _drop_typed_ahead

    NAV_START_COUNT=$started
    # Publish the ◐ rows so the next refresh tick does not load the cache
    # from before the start and draw them ○ again. The cursor stays on the
    # row r was pressed on, found by id: the rows above it did not move,
    # but the index is taken from the row rather than trusted.
    if ((started > 0)); then
        index=$(_index_of_row "$shown")
        _settle_after_change "$index" >/dev/null
        signal_view_update
    fi
    if _row_is_project "$shown"; then
        if ((failed > 0)); then
            _nav_hint "Started ${started}, ${failed} failed${NAV_START_ERR:+: $NAV_START_ERR}"
        else
            _nav_hint "Started ${started} session(s)"
        fi
    elif ((failed > 0)); then
        _nav_hint "✗ Could not start: ${NAV_START_ERR:-unknown error}"
    fi
    return 0
}

# Index of row id $1 in the list, or the saved selection index when the row
# is no longer listed.
_index_of_row() {
    local i
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        [[ "${SESSION_IDS[$i]}" == "$1" ]] && {
            echo "$i"
            return 0
        }
    done
    get_selection_index
}

# Drop keys typed while the starts held the loop. -t 0.01 makes this a
# drain, not a wait.
_drop_typed_ahead() {
    read -rsn100 -t 0.01 _ 2>/dev/null || true
}
