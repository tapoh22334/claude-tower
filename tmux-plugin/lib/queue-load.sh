#!/usr/bin/env bash
# shellcheck shell=bash
# queue-load.sh - Filling queue-view.sh's arrays: the first load, the
# reloads that run in the background, and keeping the cursor on its
# session across them. Sourced by queue-view.sh only; it works on that
# script's QUEUE_* arrays and calls its _compose_queue_rows and
# _follow_selection.

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
