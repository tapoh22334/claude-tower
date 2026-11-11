#!/usr/bin/env bats
# Acceptance scenarios for value/004-nav-r-start, one @test per scenario in
# value/004-nav-r-start/acceptance/004-nav-r-start.feature with the SAME
# names. Real tmux on the per-run test sockets; claude is a stand-in that
# logs its arguments, and the list loop's functions are driven where a key
# would be (as in test_acceptance_003.bats).

load '../test_helper'

T="$PROJECT_ROOT/tmux-plugin/scripts/tower.sh"
NAV="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"

setup() {
    FAKE_LOG="$BATS_TEST_TMPDIR/claude-args.log"
    FAKE="$BATS_TEST_TMPDIR/fake-claude"
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>%q\nexec sleep 30\n' "$FAKE_LOG" >"$FAKE"
    chmod +x "$FAKE"
    export CLAUDE_TOWER_PROGRAM="$FAKE"
    source_common
    setup_test_env
    FOO="$BATS_TEST_TMPDIR/w/foo"
    BAR="$BATS_TEST_TMPDIR/w/bar"
    mkdir -p "$FOO" "$BAR"
    FOO=$(cd "$FOO" && pwd -P)
    BAR=$(cd "$BAR" && pwd -P)
    OUT="$BATS_TEST_TMPDIR/hint.out"
}

teardown() {
    teardown_test_env
}

_nav() {
    signal_view_update() { :; }
    signal_view_update_async() { :; }
    _flush_pending_view_signal() { :; }
    _return_from_subflow() { :; }
    _subflow_tty() { echo /dev/null; }
    _spawn_background_rebuild() { :; }
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
_slug() { printf '%s' "${1//\//-}"; }
_transcript() { create_mock_jsonl "$(_slug "$2")" "${1#tower_}" "$2" >/dev/null; }
# A session in dir $1 that has a transcript and no tmux session: ○ dormant.
_dormant() {
    local s
    s=$(_open "$1")
    _transcript "$s" "$1"
    session_tmux kill-session -t "$s"
    echo "$s"
}
_index_of() {
    local i
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        [[ "${SESSION_IDS[$i]}" == "$1" ]] && { echo "$i"; return 0; }
    done
    return 1
}
_shows() { local i; i=$(_index_of "$1") && [[ "${SESSION_DISPLAYS[$i]}" == *"$2"* ]]; }
_launched() { grep -q -- "--resume ${1#tower_}" "$FAKE_LOG" 2>/dev/null; }
_launches() { wc -l <"$FAKE_LOG" 2>/dev/null || echo 0; }
_await_launch() {
    local n
    for ((n = 0; n < 100; n++)); do
        _launched "$1" && return 0
        command sleep 0.1
    done
    echo "no launch for [$1]; log:" >&2
    cat "$FAKE_LOG" >&2 2>/dev/null || true
    return 1
}
_external() {
    EXTERNAL_ID="$1"
    eval "_real_display_state() $(declare -f get_display_state | tail -n +2)"
    get_display_state() {
        if [[ "$1" == "$EXTERNAL_ID" ]]; then echo external; return 0; fi
        _real_display_state "$@"
    }
}
# Press r with the cursor on row $1, as the list loop would: the selection
# file names the row, and the row on screen is passed along.
_press_r() {
    set_nav_selected "$1"
    start_under_cursor "$1" >"$OUT" 2>&1
}

@test "休眠中の行で r を押すと、起動して一覧に留まる" {
    source "$NAV" 2>/dev/null || true
    _nav
    local s help
    s=$(_dormant "$FOO")
    build_session_list
    _shows "$s" "○"
    _press_r "$s"
    session_tmux has-session -t "$s"
    _await_launch "$s"
    _shows "$s" "◐"
    # The next refresh tick loads the cache: the ◐ must have been published
    # there, or the row flips back to ○ until the rebuild lands.
    _load_session_state
    _shows "$s" "◐"
    [ -z "$FOCUSED" ]
    [ "$(get_nav_focus)" = "list" ]
    [ "$(get_nav_selected)" = "$s" ]
    help=$(show_help </dev/null 2>/dev/null || true)
    [[ "$help" == *"  r  "* ]]
}

@test "見出しの行で r を押すと、そのプロジェクトの休眠中のセッションだけがすべて起動する" {
    source "$NAV" 2>/dev/null || true
    _nav
    local d1 d2 live ext other n
    d1=$(_dormant "$FOO")
    d2=$(_dormant "$FOO")
    live=$(_open "$FOO")
    ext=$(_dormant "$FOO")
    _external "$ext"
    other=$(_dormant "$BAR")
    build_session_list
    n=$(_launches)
    _press_r "dir:$FOO"
    _await_launch "$d1"
    _await_launch "$d2"
    _shows "$d1" "◐"
    _shows "$d2" "◐"
    grep -q "Started 2" "$OUT"
    [ "$(_launches)" -eq $((n + 2)) ]
    run _launched "$ext"
    [ "$status" -ne 0 ]
    run _launched "$other"
    [ "$status" -ne 0 ]
    run session_tmux has-session -t "$other"
    [ "$status" -ne 0 ]
    # Published to the cache, so the next tick does not redraw them ○.
    _load_session_state
    _shows "$d1" "◐"
    _shows "$d2" "◐"
    [ "$(get_nav_focus)" = "list" ]
    [ "$(get_nav_selected)" = "dir:$FOO" ]
}

@test "起動するものがない行で r を押すと、理由が出て何も起動しない" {
    source "$NAV" 2>/dev/null || true
    _nav
    local live ext n
    live=$(_open "$FOO")
    ext=$(_dormant "$FOO")
    _external "$ext"
    build_session_list
    n=$(_launches)
    _press_r "$live"
    grep -q "Already running" "$OUT"
    _press_r "$ext"
    grep -q "Running outside Tower" "$OUT"
    _press_r "dir:$BAR"
    grep -q "No dormant session" "$OUT"
    _press_r "dir:$FOO"
    grep -q "No dormant session" "$OUT"
    [ "$(_launches)" -eq "$n" ]
    run session_tmux has-session -t "$ext"
    [ "$status" -ne 0 ]
}

@test "起動に失敗した行は休眠中のまま残り、失敗が表示される" {
    source "$NAV" 2>/dev/null || true
    _nav
    local ok bad
    ok=$(_dormant "$FOO")
    bad=$(_dormant "$FOO")
    build_session_list
    # session-restore.sh failing for one session (claude missing, tmux
    # refusing): the start step for it reports failure.
    FAIL_ID="$bad"
    eval "_real_start_one() $(declare -f _start_one_session | tail -n +2)"
    _start_one_session() {
        [[ "$1" == "$FAIL_ID" ]] && return 1
        _real_start_one "$@"
    }
    _press_r "dir:$FOO"
    _await_launch "$ok"
    _shows "$ok" "◐"
    _shows "$bad" "○"
    run _launched "$bad"
    [ "$status" -ne 0 ]
    grep -q "Started 1, 1 failed" "$OUT"
}

@test "画面の行と選択の記録が一致しないときは、何も起動しない" {
    source "$NAV" 2>/dev/null || true
    _nav
    local a b n
    a=$(_dormant "$FOO")
    b=$(_dormant "$BAR")
    build_session_list
    n=$(_launches)
    set_nav_selected "$b"
    start_under_cursor "$a" >"$OUT" 2>&1
    [ "$(_launches)" -eq "$n" ]
    run session_tmux has-session -t "$a"
    [ "$status" -ne 0 ]
    run session_tmux has-session -t "$b"
    [ "$status" -ne 0 ]
}

@test "セッション行で起動に失敗すると、理由が出て休眠中のまま残る" {
    source "$NAV" 2>/dev/null || true
    _nav
    local s
    s=$(_dormant "$FOO")
    build_session_list
    # The real restore script, made to fail the way it does when tmux
    # refuses the session: a non-zero exit with the reason on stderr.
    SCRIPT_DIR="$BATS_TEST_TMPDIR/scripts"
    mkdir -p "$SCRIPT_DIR"
    printf '#!/usr/bin/env bash\necho "Error: tmux refused the session" >&2\nexit 1\n' \
        >"$SCRIPT_DIR/session-restore.sh"
    chmod +x "$SCRIPT_DIR/session-restore.sh"
    _press_r "$s"
    _shows "$s" "○"
    grep -q "Could not start: tmux refused the session" "$OUT"
    run session_tmux has-session -t "$s"
    [ "$status" -ne 0 ]
}
