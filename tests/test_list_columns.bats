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
        # State the size rather than stubbing tput. _term_cols asks the real
        # tput first, so on a machine where it can answer (CI runners can) a
        # function definition here is never consulted and the test measured
        # the runner terminal instead of the 140 columns it asked for.
        export TOWER_TERM_COLS='"$cols"'
        export TOWER_TERM_LINES=40
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/navigator-list.sh"
        set +e
        tput() { case "$1" in cols) return 1 ;; lines) return 1 ;; ed) printf "" ;; *) command tput "$@" 2>/dev/null ;; esac; }
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
    [ "$output" = "80" ]
}

@test "_content_width: uses the terminal width when between the floor and cap" {
    _run_nav 72 'echo "$(_content_width)"'
    [ "$output" = "72" ]
}

@test "_content_width: floors at NAV_MIN_WIDTH on a narrow terminal" {
    _run_nav 40 'echo "$(_content_width)"'
    [ "$output" = "50" ]
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
    # cols 100 clamps to the 80-cell cap, so the composed row (which excludes
    # the renderer's 2-space indent) must fit within 78 cells.
    _run_nav 100 '
        r=$(_compose_row "●" "a fairly long session title that keeps going and going" "$(printf "\033[2m⚙3\033[0m")")
        plain=$(printf "%s" "$r" | sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g")
        str_display_width "$plain"
    '
    [ "$status" -eq 0 ]
    [ "$output" -le 78 ]
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
        printf "%s" "${SESSION_HEADERS[0]}" | sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g" | LC_ALL=C wc -c
    '
    [ "$status" -eq 0 ]
    # "alpha" (5) + space + rule, capped at the 80-cell content width, not
    # 140. The rule glyph (─) is 3 bytes, so byte length far exceeds the
    # cell width; assert it is bounded well under a 140-wide rule.
    #
    # Count with `LC_ALL=C wc -c`, not awk's length(): in a UTF-8 locale awk
    # counts characters, so the same correct header measured 219 locally and
    # 77 on the runner. The bytes were identical both times — an od dump on
    # CI showed the expected 342 224 200 rule glyphs — and only the ruler
    # disagreed. This assertion is about byte length, so it must ask for
    # bytes rather than inherit whatever the environment's locale implies.
    #
    # Read the last line, not all of $output: bats folds the sub-shell's
    # stderr into it, so anything the sourced scripts warn about lands ahead
    # of the number and turns the comparison into a string test. That is what
    # made this fail on CI while the geometry it measures (cw=80, name=5) was
    # identical to a local run.
    local measured="${lines[${#lines[@]}-1]}"
    echo "measured header byte length: $measured" >&3
    [ "$measured" -gt 80 ]    # multibyte rule, so > 80 bytes
    [ "$measured" -lt 260 ]   # 80-cap rule ~228 bytes; a 140 rule would be ~410
}

# ---------------------------------------------------------------------------
# Terminal geometry: an explicit size wins over whatever tput can answer.
#
# _term_cols used to ask tput first and treat TOWER_TERM_COLS as a fallback
# for when it could not answer. That makes the override useless precisely
# where it is needed: on a machine where tput CAN answer, a test that states
# its width is silently overruled and measures the runner's terminal instead.
# It is why "header rule fills to the cap" passed in Docker (no tty, fallback
# used) and failed on the GitHub runner (tty present, 140 ignored) — the same
# commit, green and red at once, which reads as flakiness rather than a bug.

@test "_term_cols: an explicit TOWER_TERM_COLS beats what tput reports" {
    run bash -c '
        export TOWER_TERM_COLS=140
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh" 2>/dev/null
        tput() { case "$1" in cols) echo 37 ;; lines) echo 11 ;; *) : ;; esac; }
        _term_cols
    '
    [ "$status" -eq 0 ]
    [ "$output" = "140" ]
}

@test "_term_lines: an explicit TOWER_TERM_LINES beats what tput reports" {
    run bash -c '
        export TOWER_TERM_LINES=40
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh" 2>/dev/null
        tput() { case "$1" in cols) echo 37 ;; lines) echo 11 ;; *) : ;; esac; }
        _term_lines
    '
    [ "$status" -eq 0 ]
    [ "$output" = "40" ]
}

@test "_term_cols: falls back to tput when no size is stated" {
    run bash -c '
        unset TOWER_TERM_COLS
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh" 2>/dev/null
        tput() { case "$1" in cols) echo 37 ;; *) : ;; esac; }
        _term_cols
    '
    [ "$status" -eq 0 ]
    [ "$output" = "37" ]
}
