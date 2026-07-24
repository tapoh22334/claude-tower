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
    # TOWER_NAV_STATE_DIR is readonly (/tmp/claude-tower), so the cache file
    # is not test-isolated; clear it before and after each test.
    mkdir -p "$TOWER_NAV_STATE_DIR" 2>/dev/null || true
    rm -f "$TOWER_NAV_STATE_DIR/session-list.cache" 2>/dev/null || true
}

teardown() {
    rm -f "$TOWER_NAV_STATE_DIR/session-list.cache" 2>/dev/null || true
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
    SESSION_DIRS=("/home/iwase/working/claude-aquarium" "" "/home/iwase/working/c5017f")
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
