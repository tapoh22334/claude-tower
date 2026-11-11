#!/usr/bin/env bats
# Acceptance scenarios for value/003-nav-keys, one @test per scenario in
# value/003-nav-keys/acceptance/003-nav-keys.feature with the SAME names.
# Real tmux on the per-run test sockets; claude is a stand-in that logs its
# arguments, and the list loop's functions are driven where a key would be.

load '../test_helper'

T="$PROJECT_ROOT/tmux-plugin/scripts/tower.sh"
NAV="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"

setup() {
    # The stand-in must be in place before common.sh derives TOWER_PROGRAM.
    FAKE_LOG="$BATS_TEST_TMPDIR/claude-args.log"
    FAKE="$BATS_TEST_TMPDIR/fake-claude"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>%q\nexec sleep 30\n' "$FAKE_LOG" >"$FAKE"
    chmod +x "$FAKE"
    export CLAUDE_TOWER_PROGRAM="$FAKE"
    source_common
    setup_test_env
    FOO="$BATS_TEST_TMPDIR/w/foo"
    BAR="$BATS_TEST_TMPDIR/w/bar"
    BAZ="$BATS_TEST_TMPDIR/w/baz"
    mkdir -p "$FOO" "$BAR" "$BAZ"
    FOO=$(cd "$FOO" && pwd -P)
    BAR=$(cd "$BAR" && pwd -P)
    BAZ=$(cd "$BAZ" && pwd -P)
}

teardown() {
    teardown_test_env
}

# Each test sources the list in its own body (its `declare -a` arrays are
# local to the function that sources them), then calls this to quiet what
# needs a terminal.
_nav() {
    signal_view_update() { :; }
    signal_view_update_async() { :; }
    _flush_pending_view_signal() { :; }
    _return_from_subflow() { :; }
    _subflow_tty() { echo /dev/null; }
    clear() { :; }
    sleep() { command sleep 0; }
    tput() { return 1; }
    count_unregistered_processes_in_dir() { echo 0; }
    list_live_claude_processes() { :; }
    FOCUSED=""
    focus_view() { FOCUSED=1; set_nav_focus view; }
    set_nav_focus list
    TOWER_TERM_LINES=40
    TOWER_TERM_COLS=80
}

_open() { env -u TMUX -u TMUX_PANE "$T" open "$1" 2>/dev/null; }
_meta_count() { find "$CLAUDE_TOWER_METADATA_DIR" -name '*.meta' | wc -l; }
_slug() { printf '%s' "${1//\//-}"; }
# Give session $1 a transcript in dir $2, as Claude would after a turn.
_transcript() { create_mock_jsonl "$(_slug "$2")" "${1#tower_}" "$2" >/dev/null; }
_index_of() {
    local i
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        [[ "${SESSION_IDS[$i]}" == "$1" ]] && { echo "$i"; return 0; }
    done
    return 1
}
_select() { set_nav_selected "$1"; }
# Wait for the stand-in to log a line matching $1.
_await_launch() {
    local n
    for ((n = 0; n < 100; n++)); do
        grep -q -- "$1" "$FAKE_LOG" 2>/dev/null && return 0
        command sleep 0.1
    done
    echo "no launch matching [$1]; log:" >&2
    cat "$FAKE_LOG" >&2 2>/dev/null || true
    return 1
}
# Make $1 look like it runs outside Tower (◇).
_external() {
    EXTERNAL_ID="$1"
    eval "_real_display_state() $(declare -f get_display_state | tail -n +2)"
    get_display_state() {
        if [[ "$1" == "$EXTERNAL_ID" ]]; then echo external; return 0; fi
        _real_display_state "$@"
    }
}

@test "会話を複製すると、元の会話を引き継いだ複製が同じディレクトリに登録される" {
    source "$NAV" 2>/dev/null || true
    _nav
    local src new
    src=$(_open "$FOO")
    save_metadata "$src" "plan" "$FOO"
    _transcript "$src" "$FOO"
    local before
    before=$(cat "$CLAUDE_TOWER_METADATA_DIR/$src.meta")
    build_session_list
    _select "$src"
    copy_selected >/dev/null
    new=$(get_nav_selected)
    [[ "$new" == tower_* && "$new" != "$src" ]]
    _await_launch "--resume ${src#tower_} --fork-session --session-id ${new#tower_}"
    session_tmux has-session -t "$new"
    [ "$(session_tmux display-message -p -t "$new" '#{pane_current_path}')" = "$FOO" ]
    load_metadata "$new"
    [ "$META_SESSION_NAME" = "plan copy" ]
    local i
    i=$(_index_of "$new")
    [ "${SESSION_DIRS[$i]}" = "$FOO" ]
    [[ "${SESSION_DISPLAYS[$i]}" == *"◐"* || "${SESSION_DISPLAYS[$i]}" == *"$SPIN_PLACEHOLDER"* ]]
    [ "$(cat "$CLAUDE_TOWER_METADATA_DIR/$src.meta")" = "$before" ]
    [ "$(live_claude_id "$src")" = "${src#tower_}" ]
}

@test "複製できない行では失敗の理由が出て、複製は起動されない" {
    source "$NAV" 2>/dev/null || true
    _nav
    local bare ext out n
    bare=$(_open "$FOO")
    ext=$(_open "$BAR")
    _transcript "$ext" "$BAR"
    _external "$ext"
    build_session_list
    n=$(_meta_count)
    _select "$bare"
    out=$(copy_selected)
    [[ "$out" == *"No conversation transcript"* ]]
    _select "$ext"
    out=$(copy_selected)
    [[ "$out" == *"outside Tower"* ]]
    _select "dir:$FOO"
    out=$(copy_selected)
    [[ "$out" == *"Project row"* ]]
    [ "$(_meta_count)" -eq "$n" ]
    run grep -- --fork-session "$FAKE_LOG"
    [ "$status" -ne 0 ]
}

@test "複製の起動に失敗したらエラーを表示し、複製のメタデータを残さない" {
    source "$NAV" 2>/dev/null || true
    _nav
    local src out n
    src=$(_open "$FOO")
    _transcript "$src" "$FOO"
    build_session_list
    n=$(_meta_count)
    _select "$src"
    # A bare name found nowhere: the start refuses before creating anything.
    out=$(CLAUDE_TOWER_PROGRAM=tower-test-no-such-claude copy_selected)
    [[ "$out" == *"Copy failed"* ]]
    [ "$(_meta_count)" -eq "$n" ]
    [ "$(get_nav_selected)" = "$src" ]
}

# The labels shown, top to bottom: the non-blank label cells of the lines.
_label_col() {
    local line cell
    while IFS= read -r line; do
        cell="${line:0:3}"
        cell="${cell// /}"
        [[ "$cell" =~ ^[a-z]{1,2}$ ]] && printf '%s,' "$cell"
    done <<<"$1"
}

@test "f c b で 3 番目のプロジェクトの先頭セッションへ移る" {
    source "$NAV" 2>/dev/null || true
    _nav
    local a b c1 c2 out
    a=$(_open "$BAR")
    b=$(_open "$BAZ")
    c1=$(_open "$FOO")
    c2=$(_open "$FOO")
    build_session_list
    # bar, baz, foo in name order
    [ "${SESSION_IDS[0]}" = "dir:$BAR" ]
    go_first >/dev/null
    _jump_assign_labels
    NAV_JUMP_ACTIVE=1
    out=$(render_list 0 | _strip_ansi_str "$(cat)")
    [[ "$out" == *"aa bar"* && "$out" == *"ba baz"* && "$out" == *"ca foo"* ]]
    # The label column is the first three cells of a line; match there only,
    # since row text (paths, names) can contain any two letters.
    [ "$(_label_col "$out")" = "aa,ab,ba,bb,ca,cb,cc," ]
    NAV_JUMP_PREFIX=c
    out=$(render_list 0 | _strip_ansi_str "$(cat)")
    [ "$(_label_col "$out")" = "ca,cb,cc," ]
    _jump_end
    jump_prompt 0 >/dev/null < <(printf 'cb')
    [ "$(get_nav_selected)" = "${SESSION_IDS[$(_index_of "dir:$FOO") + 1]}" ]
    [ "$NAV_NEW_INDEX" -eq "$(($(_index_of "dir:$FOO") + 1))" ]
    [ -z "$NAV_JUMP_ACTIVE" ]
}

@test "f と見出しの 2 文字のラベルで見出しの行へ移り、1 文字目の後の Enter は取り消しになる" {
    source "$NAV" 2>/dev/null || true
    _nav
    _open "$BAR" >/dev/null
    _open "$FOO" >/dev/null
    build_session_list
    go_first >/dev/null
    jump_prompt 0 >/dev/null < <(printf 'ba')
    [ "$(get_nav_selected)" = "dir:$FOO" ]
    go_first >/dev/null
    jump_prompt 0 >/dev/null < <(printf 'b\n')
    [ "$NAV_NEW_INDEX" -eq 0 ]
    [ "$(get_nav_selected)" = "dir:$BAR" ]
}

@test "ジャンプを取り消したときや移動先が消えて失敗したときはカーソルが動かない" {
    source "$NAV" 2>/dev/null || true
    _nav
    local s1 s2
    s1=$(_open "$BAR")
    s2=$(_open "$FOO")
    build_session_list
    _select "${SESSION_IDS[1]}"
    jump_prompt 1 >/dev/null < <(printf '\033')
    [ "$NAV_NEW_INDEX" -eq 1 ]
    [ -z "$NAV_JUMP_ACTIVE" ]
    jump_prompt 1 >/dev/null < <(printf 'z')
    [ "$NAV_NEW_INDEX" -eq 1 ]
    [ "$(get_nav_selected)" = "${SESSION_IDS[1]}" ]
    # The target leaves the list between the two letters.
    render_list() {
        if [[ "$NAV_JUMP_PREFIX" == b ]]; then
            "$PROJECT_ROOT/tmux-plugin/scripts/session-delete.sh" "$s2" --force >/dev/null 2>&1
            build_session_list
        fi
    }
    NAV_NEW_INDEX=1
    jump_prompt 1 >/dev/null < <(printf 'bb')
    [ "$NAV_NEW_INDEX" -eq 1 ]
    [ "$(get_nav_selected)" = "$s1" ]
}

@test "空の一覧で f を押してもジャンプのモードに入らない" {
    source "$NAV" 2>/dev/null || true
    _nav
    build_session_list
    [ "${#SESSION_IDS[@]}" -eq 0 ]
    local rest
    rest=$( { jump_prompt 0 >/dev/null; IFS= read -rsn1 k; printf '%s' "$k"; } < <(printf 'j'))
    [ "$rest" = "j" ]
    [ -z "$NAV_JUMP_ACTIVE" ]
}

@test "複製を断られた後、会話の記録がある行でやり直すと複製できる" {
    source "$NAV" 2>/dev/null || true
    _nav
    local bare good out
    bare=$(_open "$FOO")
    good=$(_open "$FOO")
    _transcript "$good" "$FOO"
    build_session_list
    _select "$bare"
    out=$(copy_selected)
    [[ "$out" == *"No conversation transcript"* ]]
    [ "$(get_nav_selected)" = "$bare" ]
    _select "$good"
    copy_selected >/dev/null
    [[ "$(get_nav_selected)" != "$good" ]]
    load_metadata "$(get_nav_selected)"
    [ "$META_SESSION_NAME" = "copy" ]
}

@test "休眠中の行で Enter を押すと再開してから入力欄へ移る" {
    source "$NAV" 2>/dev/null || true
    _nav
    local dormant live ext i
    dormant=$(_open "$FOO")
    _transcript "$dormant" "$FOO"
    session_tmux kill-session -t "$dormant"
    live=$(_open "$BAR")
    ext=$(_open "$BAZ")
    _transcript "$ext" "$BAZ"
    session_tmux kill-session -t "$ext"
    _external "$ext"
    build_session_list
    i=$(_index_of "$dormant")
    [[ "${SESSION_DISPLAYS[$i]}" == *"○"* ]]
    _select "$dormant"
    open_selected >/dev/null
    [ "$FOCUSED" = 1 ]
    [ "$NAV_OPEN_RESUMED" = 1 ]
    session_tmux has-session -t "$dormant"
    _await_launch "--resume ${dormant#tower_}"
    i=$(_index_of "$dormant")
    [[ "${SESSION_DISPLAYS[$i]}" == *"◐"* || "${SESSION_DISPLAYS[$i]}" == *"$SPIN_PLACEHOLDER"* ]]
    local launches
    launches=$(wc -l <"$FAKE_LOG")
    for id in "$live" "$ext"; do
        FOCUSED=""
        _select "$id"
        open_selected >/dev/null
        [ "$FOCUSED" = 1 ]
        [ -z "$NAV_OPEN_RESUMED" ]
    done
    [ "$(wc -l <"$FAKE_LOG")" -eq "$launches" ]
    run session_tmux has-session -t "$ext"
    [ "$status" -ne 0 ]
}

@test "休眠中の行の再開に失敗したら、エラーを表示して一覧に留まる" {
    source "$NAV" 2>/dev/null || true
    _nav
    local s out gone="$BATS_TEST_TMPDIR/w/gone"
    mkdir -p "$gone"
    gone=$(cd "$gone" && pwd -P)
    s=$(_open "$gone")
    _transcript "$s" "$gone"
    session_tmux kill-session -t "$s"
    rm -rf "$gone"
    build_session_list
    _select "$s"
    out=$(open_selected)
    [[ "$out" == *"Failed to restore"* ]]
    [ "$(get_nav_focus)" = "list" ]
    run session_tmux has-session -t "$s"
    [ "$status" -ne 0 ]
}

@test "a の場所の初期値はカーソルの行のプロジェクトになる" {
    source "$NAV" 2>/dev/null || true
    _nav
    local s
    s=$(_open "$BAR")
    _transcript "$s" "$BAR"
    build_session_list
    get_caller_cwd() { echo /caller; }
    _select "$s"
    [ "$(_add_default_dir)" = "$BAR" ]
    _select "dir:$BAR"
    [ "$(_add_default_dir)" = "$BAR" ]
    # a on a project row is the ordinary a, not the row's own action
    run handle_project_key a "$BAR" 0
    [ "$status" -eq 1 ]
}

@test "削ったキーは何もせず、i は Enter と同じで、ヘルプに 18 個のキーが並ぶ" {
    source "$NAV" 2>/dev/null || true
    _nav
    local s n help footer k
    s=$(_open "$FOO")
    build_session_list
    _select "$s"
    n=$(_meta_count)
    # A has no branch in the loop: nothing it calls is reached. (r came back
    # as the start key in value/004-nav-r-start.)
    run grep -nE '^ {16}(i|A)( \|.*)?\)' "$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh"
    [ "$status" -ne 0 ]
    # i is read as Enter before any key is dispatched.
    grep -qE '^ +\[\[ "\$key" == i \]\] && key=""$' "$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh"
    [ "$(_meta_count)" -eq "$n" ]
    [ "$(get_nav_focus)" = "list" ]
    help=$(show_help </dev/null 2>/dev/null || true)
    for k in "j / " "k / " "g / G" "/ text" "n / N" "f x y" "Enter / i" "  a  " "  c  " "  D  " "Tab / t" "  w  " "?  " "q  Quit"; do
        [[ "$help" == *"$k"* ]] || { echo "help lacks [$k]"; return 1; }
    done
    footer=$(render_list 0 | tail -n 1)
    footer=$(_strip_ansi_str "${footer//$'\033[K'/}")
    [ "$(str_display_width "$footer")" -le 80 ]
    for k in $footer; do
        case "${k%%:*}" in
            j/k | ↵ | / | f | a | c | D | t | w | '?' | q) ;;
            *) echo "footer key not in the set: $k"; return 1 ;;
        esac
    done
}
