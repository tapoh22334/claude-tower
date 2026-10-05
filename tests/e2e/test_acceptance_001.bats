#!/usr/bin/env bats
# Acceptance scenarios for value/001-tower-session-cli, one @test per
# scenario in value/001-tower-session-cli/acceptance/scenarios.feature, with
# the SAME names (the runner maps TAP lines to scenarios by name). Runs the
# real `tower` CLI against real tmux servers on the per-run test sockets.

load '../test_helper'

T="$PROJECT_ROOT/tmux-plugin/scripts/tower.sh"
A="tower_aaaaaaaa-0000-4000-8000-00000000000a"
H="tower_bbbbbbbb-0000-4000-8000-00000000000b"

setup() {
    source_common
    setup_test_env
    export TOWER_PROJECTS_DIR="$BATS_TEST_TMPDIR/parent"
    mkdir -p "$TOWER_PROJECTS_DIR" "$BATS_TEST_TMPDIR/foo"
    FOO="$BATS_TEST_TMPDIR/foo"
}

teardown() {
    teardown_test_env
}

_tower_count() { session_tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -c '^tower_' || true; }

# Run a Tower session (program stand-in) and export TMUX/TMUX_PANE so a
# command runs "from inside" it.
_inside() {
    local id="$1"
    session_tmux new-session -d -s "$id" -c /tmp "sleep 60"
    save_metadata "$id" "" "/tmp"
    IN_PANE=$(session_tmux display-message -p -t "$id" '#{pane_id}')
    IN_SOCK=$(session_tmux display-message -p -t "$id" '#{socket_path}')
}

@test "セッションの中から引数なしで自分の名前を付け替える" {
    _inside "$A"
    local before
    before=$(grep -v '^session_name=' "$TOWER_METADATA_DIR/$A.meta")
    run --separate-stderr env TMUX="$IN_SOCK,1,0" TMUX_PANE="$IN_PANE" "$T" rename "payments 移行"
    [ "$status" -eq 0 ]
    [ "$output" = "$A" ]
    load_metadata "$A"
    [ "$META_SESSION_NAME" = "payments 移行" ]
    [ "$(grep -v '^session_name=' "$TOWER_METADATA_DIR/$A.meta")" = "$before" ]
    # The Navigator's row label on its next rebuild (navigator-list.sh only
    # runs its loop when executed, so it can be sourced for its functions)
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
    [[ "$(_session_label "$A")" == *"payments 移行"* ]]
}

@test "Tower の外で --session なしの rename は失敗して何も変えない" {
    save_metadata "$A" "" "/tmp"
    local before
    before=$(cat "$TOWER_METADATA_DIR/$A.meta")
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename foo
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"--session"* ]]
    [ "$(cat "$TOWER_METADATA_DIR/$A.meta")" = "$before" ]
}

@test "付けた名前を --clear で外す" {
    save_metadata "$A" "old name" "/tmp"
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename --clear --session "$A"
    [ "$status" -eq 0 ]
    [ "$output" = "$A" ]
    ! grep -q '^session_name=' "$TOWER_METADATA_DIR/$A.meta"
}

@test "別プロジェクトで新セッションを開始し要約を最初のプロンプトとして渡す" {
    _inside "$H"
    local before summary
    before=$(cat "$TOWER_METADATA_DIR/$H.meta")
    summary=$'目的: foo の API 設計\n決めたこと: REST\n次にやること: スキーマ案\n参照: docs/api.md'
    run --separate-stderr bash -c "printf '%s\n' \"\$1\" | env TMUX='$IN_SOCK,1,0' TMUX_PANE='$IN_PANE' '$T' open '$FOO' --prompt-file -" _ "$summary"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^tower_[0-9a-f-]{36}$ ]]
    local id="$output"
    [ "$(session_tmux display-message -p -t "$id" '#{pane_current_path}')" = "$(cd "$FOO" && pwd -P)" ]
    load_metadata "$id"
    [ "$META_LAUNCH_DIR" = "$(cd "$FOO" && pwd -P)" ]
    [ "$(cat "$TOWER_METADATA_DIR/$id.prompt")" = "$summary" ]
    sleep 0.5
    local screen
    screen=$(session_tmux capture-pane -p -J -S -50 -t "$id")
    [[ "$screen" == *"$id.prompt"* ]]
    [ "$(cat "$TOWER_NAV_SELECTED_FILE")" = "$id" ]
    session_tmux has-session -t "$H"
    [ "$(cat "$TOWER_METADATA_DIR/$H.meta")" = "$before" ]
}

@test "Navigator が動作していれば open 後に view が新セッションに切り替わる" {
    _inside "$H"
    # A Navigator whose view pane is a nested client attached to tower_H.
    TMUX= nav_tmux new-session -d -s "$TOWER_NAV_SESSION" -x 120 -y 30 "sleep 60"
    nav_tmux split-window -t "$TOWER_NAV_SESSION" -h "TMUX= tmux -L '$TOWER_SESSION_SOCKET' attach-session -t '$H'"
    local n=30
    until session_tmux list-clients -F '#{client_session}' 2>/dev/null | grep -qx "$H" || ((n-- == 0)); do sleep 0.1; done
    session_tmux list-clients -F '#{client_session}' | grep -qx "$H"

    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$FOO"
    [ "$status" -eq 0 ]
    local id="$output" m=30
    until session_tmux list-clients -F '#{client_session}' 2>/dev/null | grep -qx "$id" || ((m-- == 0)); do sleep 0.1; done
    session_tmux list-clients -F '#{client_session}' | grep -qx "$id"
}

@test "Navigator が動作していなくても open は成功する" {
    nav_tmux kill-server 2>/dev/null || true
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$FOO"
    [ "$status" -eq 0 ]
    [ "$(cat "$TOWER_NAV_SELECTED_FILE")" = "$output" ]
}

@test "存在しないディレクトリへの open は失敗しセッションを作らない" {
    local n0
    n0=$(_tower_count)
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$BATS_TEST_TMPDIR/typo"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"typo"* ]]
    [ "$(_tower_count)" -eq "$n0" ]
}

@test "新しいプロジェクトを 1 コマンドで始める" {
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project new bar --prompt "bar の初期設計を始める"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^tower_[0-9a-f-]{36}$ ]]
    [ -d "$TOWER_PROJECTS_DIR/bar/.git" ]
    local id="$output"
    [ "$(session_tmux display-message -p -t "$id" '#{pane_current_path}')" = "$(cd "$TOWER_PROJECTS_DIR/bar" && pwd -P)" ]
    [ "$(cat "$TOWER_METADATA_DIR/$id.prompt")" = "bar の初期設計を始める" ]
}

@test "既に存在する名前での project new は失敗し何も触らない" {
    mkdir -p "$TOWER_PROJECTS_DIR/bar"
    echo keep >"$TOWER_PROJECTS_DIR/bar/file"
    local n0
    n0=$(_tower_count)
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project new bar
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"lready exists"* ]]
    [ "$(cat "$TOWER_PROJECTS_DIR/bar/file")" = "keep" ]
    [ ! -e "$TOWER_PROJECTS_DIR/bar/.git" ]
    [ "$(_tower_count)" -eq "$n0" ]
}

@test "スキルから非対話で呼べる文面と契約が揃っている" {
    local skill="$PROJECT_ROOT/skills/tower/SKILL.md"
    [ -f "$skill" ]
    grep -q '^name: tower' "$skill"
    grep -q 'tower rename' "$skill"
    grep -q 'tower open' "$skill"
    grep -q 'tower project new' "$skill"
    grep -q '名前' "$skill"
    grep -q '続け' "$skill"
    grep -q '新しいプロジェクト' "$skill"
    grep -q '目的' "$skill"
    grep -q '決めたこと' "$skill"
    grep -q '次にやること' "$skill"
    grep -q '参照' "$skill"
    save_metadata "$A" "" "/tmp"
    run --separate-stderr timeout 10 env -u TMUX -u TMUX_PANE "$T" rename x --session "$A" </dev/null
    [ "$status" -eq 0 ]
}

@test "入力が不正なときは理由と終了コードで区別できて失敗する" {
    save_metadata "$A" "" "/tmp"
    local n0
    n0=$(_tower_count)
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename "" --session "$A"
    [ "$status" -eq 2 ]
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" rename x --session tower_zzzzzzzz-0000-4000-8000-00000000000z
    [ "$status" -eq 1 ]
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" open "$FOO" --prompt-file /nonexistent
    [ "$status" -eq 1 ]
    [ "$(_tower_count)" -eq "$n0" ]
    run --separate-stderr bash -c "env -u TMUX -u TMUX_PANE '$T' open '$FOO' --prompt-file - </dev/null"
    [ "$status" -eq 1 ]
    [ "$(_tower_count)" -eq "$n0" ]
    run --separate-stderr env -u TMUX -u TMUX_PANE "$T" project new ../evil
    [ "$status" -eq 2 ]
    [ -z "$(ls -A "$TOWER_PROJECTS_DIR")" ]
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/usr/bin/env bash\nexit 1\n' >"$BATS_TEST_TMPDIR/bin/git"
    chmod +x "$BATS_TEST_TMPDIR/bin/git"
    run --separate-stderr env -u TMUX -u TMUX_PANE PATH="$BATS_TEST_TMPDIR/bin:$PATH" "$T" project new baz
    [ "$status" -eq 1 ]
    [ "$(_tower_count)" -eq "$n0" ]
}

@test "help に 3 コマンドが載っている" {
    run "$T" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"rename"* ]]
    [[ "$output" == *"open"* ]]
    [[ "$output" == *"project new"* ]]
}
