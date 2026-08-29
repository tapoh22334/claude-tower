#!/usr/bin/env bats
# Session titles are whatever the user typed at Claude, rendered with printf
# into a width-budgeted frame. An escape sequence in that text repaints the
# list — colour bleeding into later rows, the cursor moving — and
# str_display_width counts its bytes as visible cells, so the row overflows
# as well. `\033[31mred\033[0m` measured 12 cells for 3 characters of text.

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

@test "title: CSI colour sequences are stripped" {
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/claude-sessions.sh" 2>/dev/null
        _first_meaningful_sentence "$(printf "\033[31mred\033[0m text")"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "red text" ]
}

@test "title: a stripped title measures its real display width" {
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/claude-sessions.sh" 2>/dev/null
        t=$(_first_meaningful_sentence "$(printf "\033[1;36mhello\033[0m")")
        str_display_width "$t"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "5" ]
}

@test "title: cursor-movement sequences are stripped too" {
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/claude-sessions.sh" 2>/dev/null
        _first_meaningful_sentence "$(printf "a\033[2Jb\033[Hc")"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "abc" ]
}

@test "title: bare control bytes are removed" {
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/claude-sessions.sh" 2>/dev/null
        _first_meaningful_sentence "$(printf "a\007b\010c")"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "abc" ]
}

@test "title: ordinary Japanese text is untouched" {
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/claude-sessions.sh" 2>/dev/null
        _first_meaningful_sentence "セッション一覧を直したい。次はテスト。"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "セッション一覧を直したい" ]
}

@test "title: emoji survive" {
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/claude-sessions.sh" 2>/dev/null
        _first_meaningful_sentence "🚀 ship it"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "🚀 ship it" ]
}

@test "title: a very long line does not hang the stripper" {
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/claude-sessions.sh" 2>/dev/null
        long=$(printf "x%.0s" {1..5000})
        t=$(_first_meaningful_sentence "$long")
        echo "${#t}"
    '
    [ "$status" -eq 0 ]
    [ "$output" -eq 5000 ]
}

@test "title: an unterminated escape does not loop forever" {
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/claude-sessions.sh" 2>/dev/null
        _first_meaningful_sentence "$(printf "before\033[")"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "before" ]
}
