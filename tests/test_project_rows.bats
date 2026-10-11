#!/usr/bin/env bats
# Project rows (value/002-project-rows): the registry, header rows in the
# list, the keys that act on a header row, the view card, `tower project rm`.

load 'test_helper'

T="$PROJECT_ROOT/tmux-plugin/scripts/tower.sh"

setup() {
    source_common
    setup_test_env
    P1="$BATS_TEST_TMPDIR/proj/alpha"
    P2="$BATS_TEST_TMPDIR/proj/beta"
    mkdir -p "$P1" "$P2"
}

teardown() {
    teardown_test_env
}

_nav() {
    # shellcheck disable=SC1090
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true
}

# --- registry ---------------------------------------------------------------

@test "registry: register_project stores the canonical path once" {
    register_project "$P1/"
    register_project "$P1"
    [ "$(list_projects)" = "$(cd "$P1" && pwd -P)" ]
    [ "$(wc -l <"$TOWER_PROJECTS_FILE")" -eq 1 ]
    project_registered "$P1"
}

@test "registry: unregister_project removes a path and fails for an unknown one" {
    register_project "$P1"
    register_project "$P2"
    unregister_project "$P1"
    [ "$(list_projects)" = "$(cd "$P2" && pwd -P)" ]
    run unregister_project "$P1"
    [ "$status" -ne 0 ]
    unregister_project "$P2"
    [ -z "$(list_projects)" ]
}

@test "registry: relative paths are refused, blank and relative lines in the file are ignored" {
    run register_project "relative/dir"
    [ "$status" -ne 0 ]
    printf '\n%s\nnot/absolute\n\n' "$P1" >"$TOWER_PROJECTS_FILE"
    [ "$(list_projects)" = "$P1" ]
}

@test "registry: the file is written with tmp+mv and does not collide with *.meta" {
    register_project "$P1"
    [ -z "$(ls "$TOWER_METADATA_DIR" | grep -v '^projects.list$')" ]
    [[ "$(list_metadata)" == "" ]]
}

@test "registry: start_claude_session registers the directory" {
    start_claude_session "tower_11111111-0000-4000-8000-000000000001" "$P1" new >/dev/null 2>&1
    project_registered "$P1"
}

@test "registry: session_project_dir and project_session_count follow launch_dir" {
    save_metadata "tower_11111111-0000-4000-8000-000000000001" "" "$P1"
    save_metadata "tower_22222222-0000-4000-8000-000000000002" "" "$P1"
    save_metadata "tower_33333333-0000-4000-8000-000000000003" "" "$P2"
    [ "$(session_project_dir tower_11111111-0000-4000-8000-000000000001)" = "$(cd "$P1" && pwd -P)" ]
    [ "$(project_session_count "$P1")" -eq 2 ]
    [ "$(project_session_count "$P2")" -eq 1 ]
    [ "$(project_session_count "$BATS_TEST_TMPDIR/none")" -eq 0 ]
}

# --- header rows in the built list -----------------------------------------

_stub_build() {
    mark_session_seen() { :; }
    init_session_seen() { :; }
    is_session_unread() { return 1; }
    count_unregistered_processes_in_dir() { echo 0; }
    list_live_claude_processes() { :; }
    build_live_id_map() { :; }
    _session_label() { echo "x"; }
}

@test "build: a registered project with no session gets a header row" {
    _nav
    _stub_build
    register_project "$P1"
    list_all_sessions() { :; }
    build_session_list
    [ "${#SESSION_IDS[@]}" -eq 1 ]
    [ "${SESSION_IDS[0]}" = "dir:$(cd "$P1" && pwd -P)" ]
    [[ "${SESSION_DISPLAYS[0]}" == *"alpha"* ]]
    [ "${SESSION_HEADERS[0]}" = "" ]
}

@test "build: groups come out as header row then members, registry and sessions merged in name order" {
    _nav
    _stub_build
    register_project "$P2"
    local a
    a=$(cd "$P1" && pwd -P)
    list_all_sessions() { echo "tower_a:active"; }
    _session_dir() { echo "$a"; }
    build_session_list
    [ "${SESSION_IDS[0]}" = "dir:$a" ]
    [ "${SESSION_IDS[1]}" = "tower_a" ]
    [ "${SESSION_IDS[2]}" = "dir:$(cd "$P2" && pwd -P)" ]
    [ "${#SESSION_IDS[@]}" -eq 3 ]
}

@test "build: with no registry file the current project dirs seed it" {
    _nav
    _stub_build
    rm -f "$TOWER_PROJECTS_FILE"
    local a
    a=$(cd "$P1" && pwd -P)
    list_all_sessions() { echo "tower_a:active"; }
    _session_dir() { echo "$a"; }
    build_session_list
    [ -f "$TOWER_PROJECTS_FILE" ]
    [ "$(list_projects)" = "$a" ]
}

@test "build: the unknown-dir group still sorts last and keeps its header row" {
    _nav
    _stub_build
    list_all_sessions() { printf 'tower_u:active\ntower_a:active\n'; }
    _session_dir() { case "$1" in tower_u) echo "" ;; *) echo "$P1" ;; esac; }
    build_session_list
    [ "${SESSION_IDS[0]}" = "dir:$P1" ]
    [ "${SESSION_IDS[2]}" = "dir:" ]
    [[ "${SESSION_DISPLAYS[2]}" == *"unknown"* ]]
    [ "${SESSION_IDS[3]}" = "tower_u" ]
}

@test "build: _project_member_count counts only session rows of that group" {
    _nav
    SESSION_IDS=(dir:/p/one tower_a tower_b dir:/p/two)
    SESSION_DIRS=(/p/one /p/one /p/one /p/two)
    [ "$(_project_member_count /p/one)" -eq 2 ]
    [ "$(_project_member_count /p/two)" -eq 0 ]
}

@test "build: header rows round-trip through the cache unchanged" {
    _nav
    SESSION_IDS=(dir:/p/one tower_a)
    SESSION_DISPLAYS=("one ───" "row a")
    SESSION_DIRS=(/p/one /p/one)
    SESSION_HEADERS=("" "")
    BROKEN_START=-1
    _publish_rebuild "$LIST_GENERATION" || true
    SESSION_IDS=()
    _load_session_state
    [ "${SESSION_IDS[0]}" = "dir:/p/one" ]
    [ "${SESSION_DISPLAYS[0]}" = "one ───" ]
}

# --- movement and selection -------------------------------------------------

@test "move: j/k stop on header rows and write dir: into selected" {
    _nav
    signal_view_update_async() { :; }
    SESSION_IDS=(dir:/p/one tower_a dir:/p/two)
    move_selection down 0 >/dev/null
    [ "$(get_nav_selected)" = "tower_a" ]
    move_selection down 1 >/dev/null
    [ "$(get_nav_selected)" = "dir:/p/two" ]
    go_first >/dev/null
    [ "$(get_nav_selected)" = "dir:/p/one" ]
}

@test "render: a selected header row is highlighted, an unselected one keeps its text" {
    _nav
    SESSION_IDS=(dir:/p/one tower_a)
    SESSION_DISPLAYS=("one ───" "row a")
    SESSION_DIRS=(/p/one /p/one)
    SESSION_HEADERS=("" "")
    BROKEN_START=-1
    get_nav_focus() { echo list; }
    _term_lines() { echo 30; }
    run render_list 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"one ───"* ]]
    [[ "$output" == *"row a"* ]]
}

# --- keys on a header row ---------------------------------------------------

@test "keys: n/Enter/f on a header start a session in that dir and seat it under the header" {
    _nav
    signal_view_update() { :; }
    signal_view_update_async() { :; }
    _return_from_subflow() { :; }
    _subflow_tty() { echo /dev/null; }
    clear() { :; }
    local a
    a=$(cd "$P1" && pwd -P)
    SESSION_IDS=("dir:$a")
    SESSION_DISPLAYS=("alpha ───")
    SESSION_DIRS=("$a")
    SESSION_HEADERS=("")
    BROKEN_START=-1
    set_nav_selected "dir:$a"
    handle_project_key "" "$a" 0
    [ "${#SESSION_IDS[@]}" -eq 2 ]
    [[ "${SESSION_IDS[1]}" == tower_* ]]
    [ "$(get_nav_selected)" = "${SESSION_IDS[1]}" ]
    [ "$NAV_NEW_INDEX" -eq 1 ]
    session_tmux has-session -t "${SESSION_IDS[1]}"
    project_registered "$a"
}

@test "keys: n on a header whose directory is gone creates nothing and keeps the row" {
    _nav
    _return_from_subflow() { :; }
    sleep() { :; }
    SESSION_IDS=(dir:/no/such/dir)
    SESSION_DISPLAYS=("dir ───")
    SESSION_DIRS=(/no/such/dir)
    SESSION_HEADERS=("")
    BROKEN_START=-1
    run handle_project_key n /no/such/dir 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Directory not found"* ]]
    [ "${#SESSION_IDS[@]}" -eq 1 ]
}

@test "keys: D on an empty header removes the project; on one with sessions it refuses" {
    _nav
    _return_from_subflow() { :; }
    sleep() { :; }
    tput() { :; }
    register_project "$P1"
    register_project "$P2"
    local a b
    a=$(cd "$P1" && pwd -P)
    b=$(cd "$P2" && pwd -P)
    SESSION_IDS=("dir:$a" "dir:$b" tower_x)
    SESSION_DISPLAYS=("alpha ───" "beta ───" "row x")
    SESSION_DIRS=("$a" "$b" "$b")
    SESSION_HEADERS=("" "" "")
    BROKEN_START=-1
    # empty project, answer y
    handle_project_key D "$a" 0 <<<"y" >/dev/null
    ! project_registered "$a"
    [ "${SESSION_IDS[0]}" = "dir:$b" ]
    # project with a session: refused, nothing changes
    run handle_project_key D "$b" 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 session"* ]]
    project_registered "$b"
    [ "${#SESSION_IDS[@]}" -eq 2 ]
}

@test "keys: i r t w Tab on a header only show a hint; movement keys fall through" {
    _nav
    _return_from_subflow() { :; }
    sleep() { :; }
    SESSION_IDS=(dir:/p/one)
    SESSION_DIRS=(/p/one)
    local k
    for k in i r t w $'\t'; do
        run handle_project_key "$k" /p/one 0
        [ "$status" -eq 0 ]
        [[ "$output" == *"Project row"* ]]
    done
    for k in j k g G q N '?'; do
        run handle_project_key "$k" /p/one 0
        [ "$status" -eq 1 ]
    done
}

@test "keys: the list loop routes a header row's keys through handle_project_key" {
    grep -q 'handle_project_key "\$key" "\$(_row_project_dir "\$cur_row")" "\$selected_index"' \
        "$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh"
}

# --- other consumers of selected --------------------------------------------

@test "consumers: nav_redirect_view with a dir: selection returns 0 and does not attach" {
    set_nav_selected "dir:$P1"
    run nav_redirect_view
    [ "$status" -eq 0 ]
}

@test "consumers: tower open with a dir: selection in place still succeeds" {
    set_nav_selected "dir:$P1"
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$P2"
    [ "$status" -eq 0 ]
}

# --- the view card ----------------------------------------------------------

@test "view: show_project_card prints directory, branch, session count and the hint" {
    git -C "$P1" init -q
    git -C "$P1" checkout -q -b feature/x 2>/dev/null || git -C "$P1" switch -q -c feature/x
    save_metadata "tower_11111111-0000-4000-8000-000000000001" "" "$P1"
    run bash -c '
        export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'"
        export CLAUDE_PROJECTS_DIR="'"$CLAUDE_PROJECTS_DIR"'"
        export CLAUDE_TOWER_NAV_STATE_DIR="'"$CLAUDE_TOWER_NAV_STATE_DIR"'"
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh" 2>/dev/null
        eval "$(sed -n "/^show_project_card() {/,/^}/p" "'"$PROJECT_ROOT"'/tmux-plugin/scripts/navigator-view.sh")"
        clear() { :; }
        show_project_card "'"$P1"'"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"Directory : $P1"* ]]
    [[ "$output" == *"Branch    : feature/x"* ]]
    [[ "$output" == *"1 session"* ]]
    [[ "$output" == *"n / Enter"* ]]
}

# --- tower project rm -------------------------------------------------------

@test "project rm: removes an empty registered project and prints the canonical path" {
    register_project "$P1"
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project rm "$P1/"
    [ "$status" -eq 0 ]
    [ "$output" = "$(cd "$P1" && pwd -P)" ]
    ! project_registered "$P1"
}

@test "project rm: refuses when sessions remain, when unregistered, and without a path" {
    register_project "$P1"
    save_metadata "tower_11111111-0000-4000-8000-000000000001" "" "$P1"
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project rm "$P1"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"1 session"* ]]
    project_registered "$P1"
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project rm "$P2"
    [ "$status" -eq 1 ]
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project rm
    [ "$status" -eq 2 ]
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project rm relative
    [ "$status" -eq 2 ]
}

@test "project rm: help lists it" {
    run "$T" help
    [[ "$output" == *"project rm"* ]]
}
