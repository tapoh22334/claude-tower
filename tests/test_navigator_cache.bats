#!/usr/bin/env bats
# test_navigator_cache.bats
#
# The refresh tick serializes the session list to a cache and reloads it,
# so build_session_list can run in the background instead of blocking the
# input loop. The round-trip must preserve every row field byte-for-byte —
# rows carry ANSI escapes, em-dashes and shell metacharacters, so a naive
# split or an unquoted eval would corrupt or execute them.

load 'test_helper'

setup() {
    source_common
    setup_test_env
    # The state dir is per run (test_helper); still clear the cache between
    # tests of this file.
    mkdir -p "$TOWER_NAV_STATE_DIR" 2>/dev/null || true
    rm -f "$TOWER_NAV_STATE_DIR/session-list.cache" 2>/dev/null || true
    rm -f "$TOWER_NAV_STATE_DIR/session-list.generation" 2>/dev/null || true
}

teardown() {
    rm -f "$TOWER_NAV_STATE_DIR/session-list.cache" 2>/dev/null || true
    rm -f "$TOWER_NAV_STATE_DIR/session-list.generation" 2>/dev/null || true
    teardown_test_env
}

source_navigator_list_functions() {
    set +euo pipefail
    # shellcheck disable=SC1090
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true
    set -euo pipefail
}

@test "session cache: round-trip preserves ANSI, em-dash, spaces and empties" {
    source_navigator_list_functions

    SESSION_IDS=("tower_aaa" "tower_bbb" "tower_ccc")
    SESSION_DISPLAYS=(
        $'\033[7m  \033[1;32m✱\033[0m name — title\033[0m'
        $'  ▶ double  spaces'
        $'  ○ plain'
    )
    SESSION_DIRS=("/home/dev/working/claude-aquarium" "" "/home/dev/working/c5017f")
    SESSION_HEADERS=($'\033[1;36maquarium\033[0m ──' "" "")
    BROKEN_START=2

    local -a oid=("${SESSION_IDS[@]}") odisp=("${SESSION_DISPLAYS[@]}")
    local -a odir=("${SESSION_DIRS[@]}") ohead=("${SESSION_HEADERS[@]}")
    local obroken=$BROKEN_START

    _serialize_session_state >"$(_session_cache_file)"

    SESSION_IDS=(); SESSION_DISPLAYS=(); SESSION_DIRS=(); SESSION_HEADERS=(); BROKEN_START=-1
    _load_session_state

    [ "${#SESSION_IDS[@]}" -eq 3 ]
    [ "$BROKEN_START" -eq "$obroken" ]
    local i
    for i in 0 1 2; do
        [ "${SESSION_IDS[$i]}" = "${oid[$i]}" ]
        [ "${SESSION_DISPLAYS[$i]}" = "${odisp[$i]}" ]
        [ "${SESSION_DIRS[$i]}" = "${odir[$i]}" ]
        [ "${SESSION_HEADERS[$i]}" = "${ohead[$i]}" ]
    done
}

@test "session cache: shell metacharacters in a row are data, never executed" {
    source_navigator_list_functions

    # A crafted title containing a command substitution must NOT run.
    local sentinel="$BATS_TEST_TMPDIR/pwned"
    SESSION_IDS=("tower_x")
    SESSION_DISPLAYS=("  \$(touch $sentinel) \`touch $sentinel\` \${x}")
    SESSION_DIRS=("/tmp")
    SESSION_HEADERS=("")
    BROKEN_START=-1

    _serialize_session_state >"$(_session_cache_file)"
    SESSION_IDS=(); SESSION_DISPLAYS=(); SESSION_DIRS=(); SESSION_HEADERS=()
    _load_session_state

    [ ! -e "$sentinel" ]                       # nothing executed
    [ "${SESSION_DISPLAYS[0]}" = "  \$(touch $sentinel) \`touch $sentinel\` \${x}" ]
}

@test "_load_session_state: returns nonzero when the cache is absent" {
    source_navigator_list_functions
    rm -f "$(_session_cache_file)"
    run _load_session_state
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Generation guard
#
# The refresh tick reloads the whole list from the cache, so a rebuild that
# started BEFORE an optimistic edit will happily write a pre-edit snapshot
# over it. The next tick then reads that snapshot back and the edit is undone:
# a deleted row reappears seconds after it vanished. Bumping a generation on
# every optimistic edit, and refusing to publish a rebuild whose generation is
# stale, is what keeps the edit from being resurrected.

@test "generation: an optimistic edit invalidates a rebuild already in flight" {
    source_navigator_list_functions

    SESSION_IDS=("tower_a" "tower_b")
    SESSION_DISPLAYS=("row a" "row b")
    SESSION_DIRS=("/p" "/p")
    SESSION_HEADERS=("" "")
    BROKEN_START=-1

    # A rebuild starts and captures the generation it began with.
    local started_at="$LIST_GENERATION"

    # The user deletes tower_b while that rebuild is still running.
    _forget_session_row tower_b
    _bump_list_generation

    # The in-flight rebuild now tries to publish its pre-delete snapshot.
    run _generation_is_current "$started_at"
    [ "$status" -ne 0 ]
}

@test "generation: a rebuild that raced nothing is still allowed to publish" {
    source_navigator_list_functions
    local started_at="$LIST_GENERATION"
    run _generation_is_current "$started_at"
    [ "$status" -eq 0 ]
}

@test "generation: a stale rebuild leaves the cache alone" {
    source_navigator_list_functions
    local cache
    cache=$(_session_cache_file)

    # The list as the user now sees it: tower_b already deleted.
    SESSION_IDS=("tower_a"); SESSION_DISPLAYS=("row a")
    SESSION_DIRS=("/p"); SESSION_HEADERS=(""); BROKEN_START=-1
    _serialize_session_state >"$cache"

    local stale_gen="$LIST_GENERATION"
    _bump_list_generation

    # A rebuild from before the delete tries to publish two rows.
    SESSION_IDS=("tower_a" "tower_b"); SESSION_DISPLAYS=("row a" "row b")
    SESSION_DIRS=("/p" "/p"); SESSION_HEADERS=("" ""); BROKEN_START=-1
    run _publish_rebuild "$stale_gen"
    [ "$status" -ne 0 ]   # refused as stale

    # Reading the cache back must NOT bring tower_b home.
    SESSION_IDS=(); SESSION_DISPLAYS=(); SESSION_DIRS=(); SESSION_HEADERS=()
    _load_session_state
    [ "${#SESSION_IDS[@]}" -eq 1 ]
    [ "${SESSION_IDS[0]}" = "tower_a" ]
}

@test "generation: a current rebuild does publish" {
    source_navigator_list_functions
    local cache
    cache=$(_session_cache_file)
    rm -f "$cache"

    local gen="$LIST_GENERATION"
    SESSION_IDS=("tower_a" "tower_b"); SESSION_DISPLAYS=("row a" "row b")
    SESSION_DIRS=("/p" "/p"); SESSION_HEADERS=("" ""); BROKEN_START=-1
    _publish_rebuild "$gen"

    SESSION_IDS=(); SESSION_DISPLAYS=(); SESSION_DIRS=(); SESSION_HEADERS=()
    _load_session_state
    [ "${#SESSION_IDS[@]}" -eq 2 ]
}

# The refresh tick reloads the arrays from the cache file. An optimistic edit
# (D → _forget_session_row → _settle_after_change) changes the arrays and bumps
# the generation, but the cache on disk is still the pre-delete snapshot. The
# next tick loads it and the deleted row is back on screen until the forced
# rebuild publishes — the "vanishes, returns after half a second, then vanishes
# for good" the user sees.
@test "settle: the next tick's cache reload does not resurrect a deleted row" {
    source_navigator_list_functions
    SESSION_IDS=(tower_a tower_b tower_c)
    SESSION_DISPLAYS=("row a" "row b" "row c")
    SESSION_DIRS=(/p /p /p)
    SESSION_HEADERS=("p ───" "" "")
    BROKEN_START=-1
    # The cache holds what the last rebuild saw: all three rows.
    _serialize_session_state >"$(_session_cache_file)"

    # Stub what settle would otherwise touch: no tmux, no rebuild fork.
    set_nav_selected() { :; }
    signal_view_update_async() { :; }
    _spawn_background_rebuild() { :; }

    # D on tower_b, exactly as the handler does it (settle runs under $(...)).
    _forget_session_row tower_b
    local idx
    idx=$(_settle_after_change 1)
    [[ " ${SESSION_IDS[*]} " != *" tower_b "* ]]

    # The very next refresh tick.
    _load_session_state
    [[ " ${SESSION_IDS[*]} " != *" tower_b "* ]]
}

# The mirror image for n/f/N: the freshly seated "starting" row must survive
# the next tick's reload too, or the session the user just made blinks out
# until the rebuild finds it.
@test "settle: the next tick's cache reload keeps a freshly added row" {
    source_navigator_list_functions
    SESSION_IDS=(tower_a)
    SESSION_DISPLAYS=("row a")
    SESSION_DIRS=(/p)
    SESSION_HEADERS=("p ───")
    BROKEN_START=-1
    _serialize_session_state >"$(_session_cache_file)"

    set_nav_selected() { :; }
    signal_view_update_async() { :; }
    _spawn_background_rebuild() { :; }
    _compose_row() { printf '%s %s' "$1" "$2"; }
    _session_label() { echo "$1"; }

    _remember_session_row tower_new /q
    local idx
    idx=$(_settle_after_change 1)
    _load_session_state
    [[ " ${SESSION_IDS[*]} " == *" tower_new "* ]]
}

# _settle_after_change used to be called as `idx=$(_settle_after_change …)`
# at every optimistic edit. Command substitution is a subshell, so the
# generation bump, the forced-rebuild bookkeeping and the coalescing PID all
# died with it: the parent's LIST_GENERATION stayed at 0, every settle wrote
# the same "1", and a rebuild that started before the FIRST edit could still
# publish over the SECOND. Movers already hand their result back through
# NAV_NEW_INDEX; settle must do the same and be called bare.
@test "settle: two edits in a row advance the generation in the calling shell" {
    source_navigator_list_functions
    SESSION_IDS=(tower_a tower_b tower_c)
    SESSION_DISPLAYS=("row a" "row b" "row c")
    SESSION_DIRS=(/p /p /p)
    SESSION_HEADERS=("" "" "")
    BROKEN_START=-1
    set_nav_selected() { :; }
    signal_view_update_async() { :; }
    _spawn_background_rebuild() { :; }

    local started_at="$LIST_GENERATION"
    _forget_session_row tower_c
    _settle_after_change 1
    local after_first="$LIST_GENERATION"
    _forget_session_row tower_b
    _settle_after_change 0
    [ "$after_first" -gt "$started_at" ]
    [ "$LIST_GENERATION" -gt "$after_first" ]
    # A rebuild that began before the first edit must still be refused after
    # the second (this is the case the $(...) form let through).
    run _generation_is_current "$started_at"
    [ "$status" -ne 0 ]
    run _generation_is_current "$after_first"
    [ "$status" -ne 0 ]
}

@test "settle: hands the clamped index back in NAV_NEW_INDEX" {
    source_navigator_list_functions
    SESSION_IDS=(tower_a tower_b)
    SESSION_DISPLAYS=("row a" "row b")
    SESSION_DIRS=(/p /p)
    SESSION_HEADERS=("" "")
    BROKEN_START=-1
    set_nav_selected() { :; }
    signal_view_update_async() { :; }
    _spawn_background_rebuild() { :; }
    _settle_after_change 7
    [ "$NAV_NEW_INDEX" -eq 1 ]
}

@test "settle: no handler calls it under command substitution" {
    # The call shape is the bug; a direct-call unit test cannot see it.
    run grep -n '^[^#]*\$(_settle_after_change' "$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh"
    [ "$status" -ne 0 ]
}

# settle asks for the confirming rebuild NOW. The tick-driven path treats a
# just-finished rebuild as the start of a cool-off, and zeroing the cool-off
# clock — settle's old way of "forcing" — is exactly what selects that branch.
# Once settle ran in the parent shell for real, every n/f/N/D/r pushed the
# confirming rebuild out by REBUILD_MIN_GAP instead of pulling it in.
@test "settle: forces a rebuild even though the last one has just finished" {
    source_navigator_list_functions
    SESSION_IDS=(tower_a)
    SESSION_DISPLAYS=("row a")
    SESSION_DIRS=(/p)
    SESSION_HEADERS=("")
    BROKEN_START=-1
    set_nav_selected() { :; }
    signal_view_update_async() { :; }
    build_session_list() { :; }
    _publish_rebuild() { :; }
    # A rebuild that finished a moment ago (dead pid, cool-off not started).
    _REBUILD_PID=4194304
    _REBUILD_DONE_AT=0
    _settle_after_change 0
    [ "$_REBUILD_PID" != "4194304" ]
    kill -0 "$_REBUILD_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}

@test "settle: with a rebuild still running, queues one for the moment it ends" {
    source_navigator_list_functions
    SESSION_IDS=(tower_a)
    SESSION_DISPLAYS=("row a")
    SESSION_DIRS=(/p)
    SESSION_HEADERS=("")
    BROKEN_START=-1
    set_nav_selected() { :; }
    signal_view_update_async() { :; }
    build_session_list() { :; }
    _publish_rebuild() { :; }
    sleep 30 &
    local running=$!
    _REBUILD_PID=$running
    _REBUILD_DONE_AT=0
    _settle_after_change 0
    # Not replaced while it runs, but remembered.
    [ "$_REBUILD_PID" = "$running" ]
    [ "$_REBUILD_WANTED" -eq 1 ]
    kill "$running" 2>/dev/null; wait "$running" 2>/dev/null || true
    # The next plain tick spawns at once instead of starting a cool-off.
    _spawn_background_rebuild
    [ "$_REBUILD_PID" != "$running" ]
    [ "$_REBUILD_WANTED" -eq 0 ]
    wait 2>/dev/null || true
}

@test "tick: a rebuild that just finished still starts the cool-off when nothing was forced" {
    source_navigator_list_functions
    build_session_list() { :; }
    _publish_rebuild() { :; }
    _REBUILD_PID=4194304
    _REBUILD_DONE_AT=0
    _spawn_background_rebuild
    [ "$_REBUILD_PID" = "4194304" ]
    [ "$_REBUILD_DONE_AT" -ne 0 ]
}

@test "generation: the bump counts up from the file, not from this process's memory" {
    source_navigator_list_functions
    printf '41\n' >"$(_generation_file)"
    LIST_GENERATION=3
    _bump_list_generation
    [ "$LIST_GENERATION" -eq 42 ]
    [ "$(cat "$(_generation_file)")" = "42" ]
}

# common.sh runs the list loop under set -e. A bare `return` after a false
# `[[ … ]] && …` returned 1 from the spawner whenever a rebuild was already
# running and the caller was the plain tick — and set -e then ended the whole
# Navigator, silently, within a minute on any real-sized list (#60).
@test "spawn: a plain tick while a rebuild is running returns 0 (set -e must not end the loop)" {
    source_navigator_list_functions
    sleep 30 &
    local running=$!
    _REBUILD_PID=$running
    _REBUILD_DONE_AT=0
    run _spawn_background_rebuild
    [ "$status" -eq 0 ]
    kill "$running" 2>/dev/null; wait "$running" 2>/dev/null || true
}

@test "spawn: every early return is 0 under set -e" {
    source_navigator_list_functions
    build_session_list() { :; }
    _publish_rebuild() { :; }
    # just finished → cool-off starts
    _REBUILD_PID=4194304; _REBUILD_DONE_AT=0
    ( set -e; _spawn_background_rebuild; echo alive-1 )
    # inside the cool-off
    _REBUILD_DONE_AT=$(_now_seconds)
    ( set -e; _spawn_background_rebuild; echo alive-2 )
    run bash -c 'echo ok'
    [ "$status" -eq 0 ]
}
