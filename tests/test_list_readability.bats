#!/usr/bin/env bats
# List readability: display-width truncation (CJK is 2 cells wide),
# meaningful-sentence titles, and the project group header.

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "str_display_width: ASCII counts one cell per character" {
    run str_display_width "abcde"
    [ "$output" = "5" ]
}

@test "str_display_width: CJK and kana count two cells each" {
    run str_display_width "日本語"
    [ "$output" = "6" ]
    run str_display_width "かわいい"
    [ "$output" = "8" ]
}

@test "str_display_width: mixed string sums both widths" {
    run str_display_width "abc日本"
    [ "$output" = "7" ]
}

@test "truncate_display: leaves a string that already fits untouched" {
    run truncate_display "short" 20
    [ "$output" = "short" ]
}

@test "truncate_display: cut string never exceeds the cell budget" {
    run truncate_display "かわいいを追及したい話" 12
    [ "$status" -eq 0 ]
    local w
    w=$(str_display_width "$output")
    [ "$w" -le 12 ]
    [[ "$output" == *"…" ]]
}

@test "truncate_display: budget is cells, not characters (regression: wrapped rows)" {
    # 10 Japanese characters = 20 cells. Counting characters would call
    # this "fits" in a 20-char budget and the row would wrap.
    run truncate_display "あいうえおかきくけこ" 20
    local w
    w=$(str_display_width "$output")
    [ "$w" -le 20 ]
}

@test "_first_meaningful_sentence: keeps only the first sentence" {
    run _first_meaningful_sentence "新しいプロジェクトを始めたい。 notionから探して"
    [ "$status" -eq 0 ]
    [ "$output" = "新しいプロジェクトを始めたい" ]
}

@test "_first_meaningful_sentence: splits on ASCII sentence terminators too" {
    run _first_meaningful_sentence "Fix the login bug. Then deploy it."
    [ "$status" -eq 0 ]
    [ "$output" = "Fix the login bug" ]
}

@test "_first_meaningful_sentence: rejects bare slash commands" {
    run _first_meaningful_sentence "/init"
    [ "$status" -ne 0 ]
    run _first_meaningful_sentence "/fork do the thing"
    [ "$status" -ne 0 ]
}

@test "_first_meaningful_sentence: rejects stock nudges and pastes" {
    run _first_meaningful_sentence "continue"
    [ "$status" -ne 0 ]
    run _first_meaningful_sentence "[Image #1]"
    [ "$status" -ne 0 ]
}

@test "_first_meaningful_sentence: flattens literal \\n escapes into spaces" {
    run _first_meaningful_sentence 'first line\nsecond line'
    [ "$status" -eq 0 ]
    [[ "$output" != *'\n'* ]]
}

@test "get_session_title: walks past a slash command to the next real prompt" {
    CLAUDE_HISTORY_FILE="${BATS_TEST_TMPDIR}/history.jsonl"
    local uuid="11111111-1111-4111-8111-111111111111"
    {
        echo '{"display":"/init","sessionId":"'"$uuid"'"}'
        echo '{"display":"make the build reproducible","sessionId":"'"$uuid"'"}'
    } > "$CLAUDE_HISTORY_FILE"
    run get_session_title "$uuid"
    [ "$status" -eq 0 ]
    [ "$output" = "make the build reproducible" ]
}

@test "get_session_title: still returns 1 when every prompt is uninformative" {
    CLAUDE_HISTORY_FILE="${BATS_TEST_TMPDIR}/history.jsonl"
    local uuid="22222222-2222-4222-8222-222222222222"
    {
        echo '{"display":"/init","sessionId":"'"$uuid"'"}'
        echo '{"display":"continue","sessionId":"'"$uuid"'"}'
    } > "$CLAUDE_HISTORY_FILE"
    run get_session_title "$uuid"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# navigator-list.sh (fresh bash: sourcing it pulls in readonly common.sh)
# ---------------------------------------------------------------------------

_run_nav() {
    run bash -c '
        export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'"
        export CLAUDE_PROJECTS_DIR="'"$CLAUDE_PROJECTS_DIR"'"
        export CLAUDE_HISTORY_FILE="'"${BATS_TEST_TMPDIR}"'/history.jsonl"
        export CLAUDE_TOWER_NAV_SOCKET="read-test-nav-$$"
        export CLAUDE_TOWER_SESSION_SOCKET="read-test-sess-$$"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/navigator-list.sh"
        set +e
        tput() { case "$1" in cols) echo 80 ;; lines) echo 24 ;; ed) printf "" ;; *) command tput "$@" 2>/dev/null ;; esac; }
        '"$1"'
    '
}

@test "_session_label: never exceeds the row budget for a long Japanese title" {
    local uuid="33333333-3333-4333-8333-333333333333"
    echo '{"display":"あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめも","sessionId":"'"$uuid"'"}' \
        > "${BATS_TEST_TMPDIR}/history.jsonl"
    _run_nav '_session_label "tower_'"$uuid"'"'
    [ "$status" -eq 0 ]
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/claude-sessions.sh"
        str_display_width "'"$output"'"
    '
    # 80-cell terminal, budget = cols - 8
    [ "$output" -le 72 ]
}

@test "_session_label: registry name leads, title follows after an em dash" {
    local uuid="44444444-4444-4444-8444-444444444444"
    echo '{"display":"do the thing","sessionId":"'"$uuid"'"}' \
        > "${BATS_TEST_TMPDIR}/history.jsonl"
    create_mock_metadata "tower_${uuid}" "my-alias"
    _run_nav '_session_label "tower_'"$uuid"'"'
    [ "$status" -eq 0 ]
    [[ "$output" == "my-alias — do the thing" ]]
}

@test "build_session_list: group header is bold-cyan with a rule, not a dim marker" {
    _run_nav '
        list_all_sessions() { echo "tower_a1:active"; }
        _session_label() { echo "x"; }
        _session_dir() { echo "/proj/alpha"; }
        mark_session_seen() { :; }
        init_session_seen() { :; }
        is_session_unread() { return 1; }
        count_unregistered_processes_in_dir() { echo 0; }
        build_session_list
        printf "%s\n" "${SESSION_HEADERS[0]}"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"─"* ]]
    # The old dim "▍dirname" treatment is gone
    [[ "$output" != *"▍"* ]]
}
