#!/usr/bin/env bats
# Deleting or adding a session used to call build_session_list inline — over a
# second on a real list — while the key loop sat in `read`. Keystrokes queued
# and arrived in a burst afterwards, so the Navigator appeared frozen right
# after the one action the user was most likely to follow up on.
#
# The handlers now apply the known outcome to the arrays already in memory and
# let the background rebuild confirm it. These pin that the in-memory edit
# keeps the four parallel arrays consistent, since a mismatch there renders a
# row against the wrong directory or header.

load 'test_helper'

setup() {
    source_common
    setup_test_env
    # shellcheck disable=SC1090
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true

    # declare -g: bats runs setup() as a function, so a plain assignment here
    # would be local to it and the arrays would read as unset in the test.
    declare -ga SESSION_IDS=(tower_a tower_b tower_c tower_d)
    declare -ga SESSION_DISPLAYS=("row a" "row b" "row c" "row d")
    declare -ga SESSION_DIRS=(/p/one /p/one /p/two /p/two)
    declare -ga SESSION_HEADERS=("one ───" "" "two ───" "")
    declare -g BROKEN_START=-1
}

_lengths() {
    echo "${#SESSION_IDS[@]} ${#SESSION_DISPLAYS[@]} ${#SESSION_DIRS[@]} ${#SESSION_HEADERS[@]}"
}

@test "forget row: removes exactly the named session" {
    _forget_session_row tower_b
    [ "${#SESSION_IDS[@]}" -eq 3 ]
    [[ " ${SESSION_IDS[*]} " != *" tower_b "* ]]
    [[ " ${SESSION_IDS[*]} " == *" tower_a "* ]]
    [[ " ${SESSION_IDS[*]} " == *" tower_d "* ]]
}

@test "forget row: the four arrays stay the same length" {
    _forget_session_row tower_c
    [ "$(_lengths)" = "3 3 3 3" ]
}

@test "forget row: rows keep their own display and directory" {
    _forget_session_row tower_b
    local i
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        case "${SESSION_IDS[$i]}" in
            tower_a) [ "${SESSION_DISPLAYS[$i]}" = "row a" ] && [ "${SESSION_DIRS[$i]}" = "/p/one" ] ;;
            tower_c) [ "${SESSION_DISPLAYS[$i]}" = "row c" ] && [ "${SESSION_DIRS[$i]}" = "/p/two" ] ;;
            tower_d) [ "${SESSION_DISPLAYS[$i]}" = "row d" ] && [ "${SESSION_DIRS[$i]}" = "/p/two" ] ;;
        esac
    done
}

@test "forget row: deleting a group's first row hands the header to the next" {
    # tower_c carries "two ───" for the group tower_c/tower_d share. Removing
    # it must not take the group's heading off the screen.
    _forget_session_row tower_c
    local i seen=""
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        [ "${SESSION_IDS[$i]}" = "tower_d" ] && seen="${SESSION_HEADERS[$i]}"
    done
    [ "$seen" = "two ───" ]
}

@test "forget row: deleting a non-first row leaves headers alone" {
    _forget_session_row tower_d
    [ "${SESSION_HEADERS[0]}" = "one ───" ]
    [ "${SESSION_HEADERS[2]}" = "two ───" ]
}

@test "forget row: an unknown id changes nothing and reports failure" {
    run _forget_session_row tower_nope
    [ "$status" -ne 0 ]
    [ "${#SESSION_IDS[@]}" -eq 4 ]
}

@test "forget row: BROKEN_START follows the rows it points at" {
    declare -g BROKEN_START=2   # tower_c is the first broken row
    _forget_session_row tower_a
    [ "${SESSION_IDS[$BROKEN_START]}" = "tower_c" ]
}

@test "forget row: removing the last remaining row empties the list" {
    declare -ga SESSION_IDS=(tower_only)
    declare -ga SESSION_DISPLAYS=("only")
    declare -ga SESSION_DIRS=(/p)
    declare -ga SESSION_HEADERS=("p ───")
    _forget_session_row tower_only
    [ "${#SESSION_IDS[@]}" -eq 0 ]
}

@test "settle: clamps the cursor into the shortened list" {
    set_nav_selected tower_d
    _forget_session_row tower_d
    run _settle_after_change 3
    [ "$status" -eq 0 ]
    [ "$output" -le 2 ]
}

@test "settle: an empty list clears the selection rather than indexing it" {
    declare -ga SESSION_IDS=()
    declare -ga SESSION_DISPLAYS=()
    declare -ga SESSION_DIRS=()
    declare -ga SESSION_HEADERS=()
    run _settle_after_change 0
    [ "$status" -eq 0 ]
    [ "$(get_nav_selected)" = "" ]
}

# ----------------------------------------------------------------------------
# Marking a row as deleting, rather than dropping it the instant D is pressed.
# The delete itself is synchronous, but the row vanishing with no trace left
# the user unable to tell a delete from a mis-keyed cursor move.
# ----------------------------------------------------------------------------

@test "mark deleting: replaces the row's display, keeps it in the list" {
    _mark_session_deleting tower_b
    [ "${#SESSION_IDS[@]}" -eq 4 ]
    [ "${SESSION_IDS[1]}" = "tower_b" ]
    [ "${SESSION_DISPLAYS[1]}" != "row b" ]
}

@test "mark deleting: the four arrays stay the same length" {
    _mark_session_deleting tower_c
    [ "$(_lengths)" = "4 4 4 4" ]
}

@test "mark deleting: leaves the row's directory and header alone" {
    _mark_session_deleting tower_c
    [ "${SESSION_DIRS[2]}" = "/p/two" ]
    [ "${SESSION_HEADERS[2]}" = "two ───" ]
}

@test "mark deleting: other rows are untouched" {
    _mark_session_deleting tower_b
    [ "${SESSION_DISPLAYS[0]}" = "row a" ]
    [ "${SESSION_DISPLAYS[2]}" = "row c" ]
    [ "${SESSION_DISPLAYS[3]}" = "row d" ]
}

@test "mark deleting: an unknown id changes nothing and reports failure" {
    run _mark_session_deleting tower_nope
    [ "$status" -ne 0 ]
}

@test "mark deleting: a failed delete can restore the original row" {
    local before="${SESSION_DISPLAYS[1]}"
    _mark_session_deleting tower_b
    _restore_session_row tower_b "$before"
    [ "${SESSION_DISPLAYS[1]}" = "row b" ]
    [ "${#SESSION_IDS[@]}" -eq 4 ]
}
