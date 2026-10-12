#!/usr/bin/env bats
# Acceptance scenarios for value/002-project-rows, one @test per scenario in
# value/002-project-rows/acceptance/scenarios.feature with the SAME names.
# Real tmux on the per-run test sockets; the list loop's functions are
# driven directly where a key press would be.

load '../test_helper'

T="$PROJECT_ROOT/tmux-plugin/scripts/tower.sh"

setup() {
    source_common
    setup_test_env
    FOO="$BATS_TEST_TMPDIR/w/foo"
    BAR="$BATS_TEST_TMPDIR/w/bar"
    BAZ="$BATS_TEST_TMPDIR/w/baz"
    mkdir -p "$FOO" "$BAR" "$BAZ"
    FOO=$(cd "$FOO" && pwd -P)
    BAR=$(cd "$BAR" && pwd -P)
    BAZ=$(cd "$BAZ" && pwd -P)
    # shellcheck disable=SC1090
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true
    # Quiet the parts that need a terminal.
    signal_view_update() { :; }
    signal_view_update_async() { :; }
    _return_from_subflow() { :; }
    _subflow_tty() { echo /dev/null; }
    clear() { :; }
    sleep() { command sleep 0; }
    tput() { :; }
    count_unregistered_processes_in_dir() { echo 0; }
    list_live_claude_processes() { :; }
}

teardown() {
    teardown_test_env
}

_ids() { printf '%s ' "${SESSION_IDS[@]}"; }
_open() { env -u TMUX -u TMUX_PANE "$T" open "$1" 2>/dev/null; }
_tower_count() { session_tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -c '^tower_' || true; }

@test "プロジェクトのセッションを全部消しても見出しが残る" {
    local s1 s2
    s1=$(_open "$FOO")
    s2=$(_open "$FOO")
    project_registered "$FOO"
    build_session_list
    [[ "$(_ids)" == "dir:$FOO "* ]]
    [ "${#SESSION_IDS[@]}" -eq 3 ]
    "$PROJECT_ROOT/tmux-plugin/scripts/session-delete.sh" "$s1" --force >/dev/null 2>&1
    "$PROJECT_ROOT/tmux-plugin/scripts/session-delete.sh" "$s2" --force >/dev/null 2>&1
    build_session_list
    [ "$(_ids)" = "dir:$FOO " ]
    project_registered "$FOO"
}

@test "台帳が無い初回は現在のプロジェクトで初期化され、壊れた行は無視される" {
    _open "$FOO" >/dev/null
    _open "$BAR" >/dev/null
    rm -f "$TOWER_PROJECTS_FILE"
    build_session_list
    [ -f "$TOWER_PROJECTS_FILE" ]
    [ "$(list_projects | sort)" = "$(printf '%s\n%s\n' "$BAR" "$FOO")" ]
    printf '\nrelative/path\n' >>"$TOWER_PROJECTS_FILE"
    build_session_list
    local n=0 id
    for id in "${SESSION_IDS[@]}"; do [[ "$id" == dir:* ]] && n=$((n + 1)); done
    [ "$n" -eq 2 ]
}

@test "j/k で見出しにカーソルが止まり selected に dir: が書かれる" {
    register_project "$FOO"
    local s
    s=$(_open "$BAR")
    build_session_list
    # bar sorts before foo: dir:bar, session, dir:foo
    [ "$(_ids)" = "dir:$BAR $s dir:$FOO " ]
    go_first >/dev/null
    [ "$(get_nav_selected)" = "dir:$BAR" ]
    move_selection down 0 >/dev/null
    [ "$(get_nav_selected)" = "$s" ]
    move_selection down 1 >/dev/null
    [ "$(get_nav_selected)" = "dir:$FOO" ]
    _publish_rebuild "$LIST_GENERATION" || true
    grep -q "^ROW dir:" "$(_session_cache_file)"
}

@test "見出しを選ぶと右 pane がプロジェクトのカードを描く" {
    git -C "$FOO" init -q
    register_project "$FOO"
    local h="tower_bbbbbbbb-0000-4000-8000-00000000000b"
    session_tmux new-session -d -s "$h" -c /tmp "sleep 60"
    save_metadata "$h" "" "$BAR"
    set_nav_selected "$h"
    # The real view pane process on the Navigator test server.
    TMUX= nav_tmux new-session -d -s "$TOWER_NAV_SESSION" -x 120 -y 30 "sleep 60"
    nav_tmux split-window -t "$TOWER_NAV_SESSION" -h -e "CLAUDE_TOWER_METADATA_DIR=$CLAUDE_TOWER_METADATA_DIR" \
        -e "CLAUDE_TOWER_NAV_STATE_DIR=$CLAUDE_TOWER_NAV_STATE_DIR" -e "CLAUDE_PROJECTS_DIR=$CLAUDE_PROJECTS_DIR" \
        -e "CLAUDE_TOWER_SESSION_SOCKET=$CLAUDE_TOWER_SESSION_SOCKET" -e "CLAUDE_TOWER_NAV_SOCKET=$CLAUDE_TOWER_NAV_SOCKET" \
        "$PROJECT_ROOT/tmux-plugin/scripts/navigator-view.sh"
    local n=50
    until session_tmux list-clients -F '#{client_session}' 2>/dev/null | grep -qx "$h" || ((n-- == 0)); do command sleep 0.1; done
    session_tmux list-clients -F '#{client_session}' | grep -qx "$h"

    set_nav_selected "dir:$FOO"
    nav_redirect_view
    n=50
    local screen=""
    until [[ "$screen" == *"a / Enter"* ]] || ((n-- == 0)); do
        command sleep 0.1
        screen=$(nav_tmux capture-pane -p -J -t "$TOWER_NAV_SESSION:0.1" 2>/dev/null || true)
    done
    [[ "$screen" == *"foo"* ]]
    [[ "$screen" == *"Directory : $FOO"* ]]
    [[ "$screen" == *"Branch"* ]]
    [[ "$screen" == *"0 session"* ]]
    [[ "$screen" == *"a / Enter"* ]]
    ! session_tmux list-clients -F '#{client_session}' 2>/dev/null | grep -qx "$h"
}

@test "selected が dir: でも他の view と CLI は落ちない" {
    set_nav_selected "dir:$FOO"
    run nav_redirect_view
    [ "$status" -eq 0 ]
    run bash -c 'export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'" CLAUDE_TOWER_NAV_STATE_DIR="'"$CLAUDE_TOWER_NAV_STATE_DIR"'" CLAUDE_PROJECTS_DIR="'"$CLAUDE_PROJECTS_DIR"'" CLAUDE_TOWER_SESSION_SOCKET="'"$CLAUDE_TOWER_SESSION_SOCKET"'" CLAUDE_TOWER_NAV_SOCKET="'"$CLAUDE_TOWER_NAV_SOCKET"'"
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh" 2>/dev/null
        for f in tile.sh tail-view.sh queue-view.sh; do
            eval "$(sed -n "/^_seed_selection() {/,/^}/p" "'"$PROJECT_ROOT"'/tmux-plugin/scripts/$f")" 2>/dev/null || true
            SESSION_IDS=(); QUEUE_IDS=(); SELECTED_ID=""; selected_index=0; CURSOR=0
            _seed_selection 2>/dev/null || true
        done
        echo alive'
    [ "$status" -eq 0 ]
    [[ "$output" == *"alive"* ]]
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$BAR"
    [ "$status" -eq 0 ]
}

@test "見出しだけの一覧や空の一覧でも操作で落ちない" {
    register_project "$FOO"
    build_session_list
    [ "$(_ids)" = "dir:$FOO " ]
    go_first >/dev/null
    move_selection down 0 >/dev/null
    move_selection up 0 >/dev/null
    [ "$(get_nav_selected)" = "dir:$FOO" ]
    run bash -c 'set -e; handle_project_key() { :; }; echo alive'
    handle_project_key D "$FOO" 0 <<<"n" >/dev/null
    [ "$(_ids)" = "dir:$FOO " ]
    unregister_project "$FOO"
    build_session_list
    [ "${#SESSION_IDS[@]}" -eq 0 ]
    go_first >/dev/null
    move_selection down 0 >/dev/null
    [ "$NAV_NEW_INDEX" -eq 0 ]
}

@test "見出しで a を押すとそのプロジェクトで新セッションが見出し直下に現れて選ばれる" {
    register_project "$FOO"
    register_project "$BAR"
    build_session_list
    set_nav_selected "dir:$FOO"
    local key
    for key in "" a f; do
        local before=${#SESSION_IDS[@]}
        handle_project_key "$key" "$FOO" "$(get_selection_index)"
        [ "${#SESSION_IDS[@]}" -eq $((before + 1)) ]
        local sel
        sel=$(get_nav_selected)
        [[ "$sel" == tower_* ]]
        [ "$(session_tmux display-message -p -t "$sel" '#{pane_current_path}')" = "$FOO" ]
        # the new row sits right after dir:FOO (id order among members)
        local i
        for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
            [[ "${SESSION_IDS[$i]}" == "dir:$FOO" ]] && break
        done
        [[ "${SESSION_IDS[$((i + 1))]}" == tower_* ]]
        [ "${SESSION_DIRS[$((i + 1))]}" = "$FOO" ]
        set_nav_selected "dir:$FOO"
    done
}

@test "ディレクトリが消えた見出しで a を押しても失敗してセッションを作らない" {
    local gone="$BATS_TEST_TMPDIR/w/gone"
    mkdir -p "$gone"
    gone=$(cd "$gone" && pwd -P)
    register_project "$gone"
    rmdir "$gone"
    build_session_list
    [ "$(_ids)" = "dir:$gone " ]
    local n0
    n0=$(_tower_count)
    run handle_project_key a "$gone" 0
    [ "$status" -eq 0 ]
    [[ "$output" == *"Directory not found"* ]]
    [ "$(_tower_count)" -eq "$n0" ]
    build_session_list
    [ "$(_ids)" = "dir:$gone " ]
}

@test "見出しでの D はセッション 0 なら台帳から外し、あれば断る" {
    register_project "$FOO"
    local s
    s=$(_open "$BAR")
    build_session_list
    # foo: empty → removed
    handle_project_key D "$FOO" "$(set_nav_selected "dir:$FOO"; get_selection_index)" <<<"y" >/dev/null
    ! project_registered "$FOO"
    [[ "$(_ids)" != *"dir:$FOO"* ]]
    # bar: has a session → refused
    set_nav_selected "dir:$BAR"
    run handle_project_key D "$BAR" "$(get_selection_index)"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 session"* ]]
    project_registered "$BAR"
    session_tmux has-session -t "$s"
}

@test "tower project rm はセッション 0 のときだけ台帳から外し help に載っている" {
    register_project "$BAZ"
    _open "$BAR" >/dev/null
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project rm "$BAZ"
    [ "$status" -eq 0 ]
    [ "$output" = "$BAZ" ]
    ! project_registered "$BAZ"
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project rm "$BAR"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"1 session"* ]]
    project_registered "$BAR"
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project rm "$BATS_TEST_TMPDIR/w/unregistered"
    [ "$status" -eq 1 ]
    run "$T" help
    [[ "$output" == *"project rm"* ]]
}

@test "見出しで i r t w を押しても何も変わらずヒントが出る" {
    register_project "$FOO"
    build_session_list
    set_nav_selected "dir:$FOO"
    local k
    for k in i r t w; do
        run handle_project_key "$k" "$FOO" 0
        [ "$status" -eq 0 ]
        [[ "$output" == *"Project row"* ]]
    done
    [ "$(get_nav_selected)" = "dir:$FOO" ]
    [ "$(_ids)" = "dir:$FOO " ]
}
