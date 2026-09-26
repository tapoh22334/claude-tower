#!/usr/bin/env bash
# shellcheck shell=bash
# nav-cache.sh - Keeping the expensive rebuild off the input thread.
#
# Owns the on-disk cache of the built list, the generation guard that stops a
# stale rebuild from publishing over an optimistic edit, and the single
# coalesced background rebuild.

# ----------------------------------------------------------------------------
# Background rebuild + cache
#
# build_session_list is expensive (per-session state detection, per-row jsonl
# greps, per-dir live-process scans) — measured well into the seconds. Run on
# the input thread it stalls `read`, so any j/k pressed during a refresh is
# buffered and lands late: the intermittent navigation lag. So the refresh
# tick never builds inline. It (a) loads the last cached result instantly and
# (b) spawns ONE background rebuild that writes a fresh cache; the next tick
# swaps that in. The cursor loop keeps running throughout.
# ----------------------------------------------------------------------------

# Cache path for the serialized list (per user, alongside the nav state).
_session_cache_file() {
    echo "${TOWER_NAV_STATE_DIR:-/tmp/claude-tower}/session-list.cache"
}

# Generation guard for optimistic edits.
#
# A rebuild runs in a subshell for seconds, then publishes what it found. If
# the user deleted a row while it was running, that snapshot still contains
# the row — publishing it puts the row back into the cache, and the next
# refresh tick loads it into the arrays. The row the user watched disappear
# returns a couple of seconds later, then leaves again once a newer rebuild
# lands. From the outside the list simply lies.
#
# Every optimistic edit bumps the generation. A rebuild carries the generation
# it began with and may only publish while that is still current. A rebuild
# that raced an edit is dropped: the optimistic arrays already hold the right
# answer, and the forced rebuild that _settle_after_change kicks off will
# produce a fresh snapshot shortly.
# The counter lives in a file, not just a variable: the rebuild runs in a
# background subshell, which gets a frozen copy of every variable at fork
# time. A bump in the parent would be invisible to it, which is precisely the
# race being closed. The file is read fresh at publish time instead.
LIST_GENERATION=0

_generation_file() {
    echo "${TOWER_NAV_STATE_DIR:-/tmp/claude-tower}/session-list.generation"
}

_bump_list_generation() {
    # Count up from the value on disk, not from this process's memory: two
    # list loops can coexist (q only detaches; the pane-exited hook respawns),
    # and a loop whose memory lags the file would otherwise re-issue a number
    # a rebuild elsewhere already holds, letting that rebuild publish over
    # this loop's edit.
    LIST_GENERATION=$(($(_current_generation) + 1))
    local f
    f=$(_generation_file)
    mkdir -p "$(dirname "$f")" 2>/dev/null || true
    printf '%s\n' "$LIST_GENERATION" >"$f" 2>/dev/null || true
}

# The generation as it stands on disk, which is what a forked rebuild must
# compare against. Falls back to the in-process value when the file is not
# readable, so a broken state dir degrades to the old behaviour rather than
# refusing every publish.
_current_generation() {
    local f val
    f=$(_generation_file)
    if [[ -r "$f" ]] && read -r val <"$f" 2>/dev/null && [[ -n "$val" ]]; then
        echo "$val"
        return
    fi
    echo "$LIST_GENERATION"
}

# 0 if $1 is still the current generation (nothing changed underneath).
_generation_is_current() {
    [[ "${1:-}" == "$(_current_generation)" ]]
}

# Write the current arrays to the cache, but only if generation $1 still
# holds. Returns 1 when the write was refused as stale.
_publish_rebuild() {
    local started_at="${1:-}"
    _generation_is_current "$started_at" || return 1
    local cache tmp
    cache=$(_session_cache_file)
    tmp="${cache}.$$"
    _serialize_session_state >"$tmp" 2>/dev/null && mv -f "$tmp" "$cache" 2>/dev/null
    rm -f "$tmp" 2>/dev/null
    return 0
}

# Serialize the current arrays to stdout. One row per line, fields quoted with
# printf %q so ANSI escapes, spaces and the em-dash survive a round-trip. A
# leading meta line carries BROKEN_START; each row line is idx-agnostic.
_serialize_session_state() {
    printf 'BROKEN_START %s\n' "$BROKEN_START"
    local i
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        printf 'ROW %q %q %q %q\n' \
            "${SESSION_IDS[$i]}" \
            "${SESSION_DISPLAYS[$i]}" \
            "${SESSION_DIRS[$i]}" \
            "${SESSION_HEADERS[$i]}"
    done
}

# Load arrays from the cache file. Returns 1 if the cache is missing/empty so
# the caller can fall back to a synchronous build the very first time.
_load_session_state() {
    local cache
    cache=$(_session_cache_file)
    [[ -s "$cache" ]] || return 1

    local -a ids=() disp=() dirs=() heads=()
    local broken=-1
    local tag a b c d
    while read -r tag rest; do
        case "$tag" in
            BROKEN_START) broken="$rest" ;;
            ROW)
                # Re-split the four %q-quoted fields safely via eval into an
                # array — %q output is valid shell word syntax by construction.
                eval "local -a f=($rest)"
                ids+=("${f[0]}")
                disp+=("${f[1]}")
                dirs+=("${f[2]}")
                heads+=("${f[3]}")
                ;;
        esac
    done <"$cache"

    SESSION_IDS=("${ids[@]}")
    SESSION_DISPLAYS=("${disp[@]}")
    SESSION_DIRS=("${dirs[@]}")
    SESSION_HEADERS=("${heads[@]}")
    BROKEN_START=$broken
    return 0
}

# Spawn ONE background rebuild. It builds into a fresh subshell (so it can't
# touch our live arrays), serializes to a temp file, then atomically renames
# it over the cache. Coalesced on a PID: a second spawn while one is running
# is a no-op, so a burst of ticks doesn't fork a pile of scanners.
#
# The PID guard alone is not enough to keep the machine quiet. It stops two
# rebuilds overlapping, but if a rebuild takes longer than the refresh
# interval — which it does on any busy machine — the very next tick starts
# another the instant one finishes. There is no gap, and the scanner runs
# continuously: a Navigator left open for ten days sat at 42% CPU doing
# exactly this.
#
# So also require REBUILD_MIN_GAP seconds of quiet since the last rebuild
# ENDED. The list still refreshes on its own; it just stops treating "as
# often as physically possible" as the target.
readonly REBUILD_MIN_GAP="${TOWER_REBUILD_MIN_GAP:-5}"

# Seconds now. EPOCHSECONDS is a bash 5 builtin; the project supports 4.0+
# (and macOS still ships 3.2), so fall back to date on older shells. The
# fallback costs a fork, but only once per refresh tick, not per row.
if [[ -n "${EPOCHSECONDS+set}" ]]; then
    _now_seconds() { echo "$EPOCHSECONDS"; }
else
    _now_seconds() { date +%s; }
fi

_REBUILD_PID=""
_REBUILD_DONE_AT=0
# Set when a forced rebuild was asked for while one was still running: the
# next call spawns as soon as that one is gone, skipping the cool-off.
_REBUILD_WANTED=0
#
# $1 = "force": the caller just changed the list and wants the confirming
# rebuild now, not after the cool-off. Without it the tick-driven path
# applies: a rebuild that has just finished starts the cool-off, and a spawn
# inside the cool-off is a no-op. Settle used to fake "force" by zeroing
# _REBUILD_DONE_AT — which, once it actually ran in the parent shell, took
# the "just finished, start the cool-off from now" branch and *delayed* the
# rebuild by REBUILD_MIN_GAP instead of forcing it.
_spawn_background_rebuild() {
    local force="${1:-}"
    local now
    now=$(_now_seconds)
    if [[ -n "$_REBUILD_PID" ]] && kill -0 "$_REBUILD_PID" 2>/dev/null; then
        # One is running. It may predate the edit that asked for this, and
        # the generation guard will then refuse its publish — so remember
        # to run another the moment it is gone.
        #
        # Explicit status: common.sh puts the whole list loop under set -e,
        # and a bare `return` after a false `[[ … ]] &&` hands back 1 — which
        # killed the Navigator silently on every tick that overlapped a
        # running rebuild (real lists rebuild for seconds; the isolated
        # tests never did, which is why they stayed green).
        if [[ -n "$force" ]]; then
            _REBUILD_WANTED=1
        fi
        return 0
    fi
    if [[ -z "$force" && $_REBUILD_WANTED -eq 0 ]]; then
        if [[ -n "$_REBUILD_PID" && $_REBUILD_DONE_AT -eq 0 ]]; then
            # It finished since we last looked; start the cool-off from now.
            _REBUILD_DONE_AT=$now
            return 0
        fi
        if ((now - _REBUILD_DONE_AT < REBUILD_MIN_GAP)); then
            return 0
        fi
    fi
    _REBUILD_WANTED=0
    _REBUILD_DONE_AT=0
    local started_at
    started_at=$(_current_generation)
    (
        # Subshell: build_session_list mutates only this copy of the arrays.
        # The publish is refused if an optimistic edit landed while we built,
        # so a pre-edit snapshot can never overwrite what the user just saw.
        build_session_list
        _publish_rebuild "$started_at"
    ) >/dev/null 2>&1 &
    _REBUILD_PID=$!
}
