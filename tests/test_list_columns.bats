#!/usr/bin/env bats
# List column alignment and max-width cap.
# navigator-list.sh sources common.sh (readonly), so these run in a fresh
# bash per the established pattern.

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# $1 = tput cols to fake, $2 = snippet
_run_nav() {
    local cols="$1" snippet="$2"
    run bash -c '
        export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'"
        export CLAUDE_PROJECTS_DIR="'"$CLAUDE_PROJECTS_DIR"'"
        export CLAUDE_TOWER_NAV_SOCKET="col-test-nav-$$"
        export CLAUDE_TOWER_SESSION_SOCKET="col-test-sess-$$"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/navigator-list.sh"
        set +e
        tput() { case "$1" in cols) echo '"$cols"' ;; lines) echo 40 ;; ed) printf "" ;; *) command tput "$@" 2>/dev/null ;; esac; }
        '"$snippet"'
    '
}

_visible_width() {
    # strip ANSI, measure display cells
    bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/claude-sessions.sh"
        plain=$(printf "%s" "'"$1"'" | sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g")
        str_display_width "$plain"
    '
}

@test "_content_width: caps at NAV_MAX_WIDTH on a wide terminal" {
    _run_nav 140 'echo "$(_content_width)"'
    [ "$output" = "100" ]
}

@test "_content_width: uses the terminal width when under the cap" {
    _run_nav 72 'echo "$(_content_width)"'
    [ "$output" = "72" ]
}

@test "_compose_row: marks land in the fixed right column (rows align)" {
    _run_nav 80 '
        a=$(_compose_row "●" "short" "$(printf "\033[32m✱\033[0m")")
        b=$(_compose_row "▶" "a much longer title here" "$(printf "\033[32m✱\033[0m")")
        strip() { sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g"; }
        wa=$(printf "%s" "$a" | strip | awk "{print length}")
        wb=$(printf "%s" "$b" | strip | awk "{print length}")
        echo "$wa $wb"
    '
    [ "$status" -eq 0 ]
    # Both rows end at the same column, so the ✱ lines up
    local wa="${output% *}" wb="${output#* }"
    [ "$wa" = "$wb" ]
}

@test "_compose_row: a row without marks gets no trailing padding" {
    _run_nav 80 '
        r=$(_compose_row "●" "short" "")
        printf "%s" "$r" | sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "● short" ]
}

@test "_compose_row: total visible width never exceeds the content width" {
    _run_nav 100 '
        r=$(_compose_row "●" "a fairly long session title that keeps going and going" "$(printf "\033[2m⚙3\033[0m")")
        plain=$(printf "%s" "$r" | sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g")
        str_display_width "$plain"
    '
    [ "$status" -eq 0 ]
    # The 2-space indent is added by the renderer; the composed row itself
    # (icon + space + label + pad + right column) must fit within the
    # content width minus that indent. Measured in cells, not bytes.
    [ "$output" -le 98 ]
}

@test "strip_ansi_seq: removes color codes, keeps text" {
    run bash -c '
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null
        printf "\033[32m✱\033[0m x" | strip_ansi_seq
    '
    [ "$status" -eq 0 ]
    [ "$output" = "✱ x" ]
}

@test "build_session_list: header rule fills to the cap, not the raw terminal" {
    _run_nav 140 '
        list_all_sessions() { echo "tower_a1:active"; }
        _session_label() { echo "x"; }
        _session_dir() { echo "/proj/alpha"; }
        mark_session_seen() { :; }
        init_session_seen() { :; }
        is_session_unread() { return 1; }
        count_unregistered_processes_in_dir() { echo 0; }
        build_session_list
        printf "%s" "${SESSION_HEADERS[0]}" | sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g" | awk "{print length}"
    '
    [ "$status" -eq 0 ]
    # "alpha" (5) + space + rule, capped near 100 cells not 140. The rule
    # chars are multibyte so byte length > cell width; assert it is bounded.
    [ "$output" -gt 100 ]   # multibyte, so > 100 bytes
    [ "$output" -lt 320 ]   # but nowhere near a 140-wide rule (~420 bytes)
}
