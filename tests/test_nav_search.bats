#!/usr/bin/env bats
# Navigator `/` search (#82), vim-style: matching, n/N stepping, the prompt
# sub-loop, the header note, and the loop wiring (n/N are always search keys;
# add / new-in-dir moved to a / A).

load 'test_helper'

NAV="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"

setup() {
    source_common
    setup_test_env
}

# The nav files `declare -a` their arrays, which is local to whichever
# function sources them — so each test sources navigator-list.sh in its own
# body and then calls this to seat the list.
_fixture() {
    signal_view_update_async() { :; }
    _flush_pending_view_signal() { :; }
    TOWER_TERM_LINES=24
    TOWER_TERM_COLS=80
    tput() { return 1; }

    SESSION_IDS=("dir:/p/alpha" "tower_a" "tower_b" "tower_c" "tower_d")
    SESSION_DISPLAYS=(
        $'\033[1;36malpha\033[0m ─────'
        $'▶ fix the \033[1mLogin\033[0m bug'
        "○ write docs"
        "@@SPIN@@ refactor login flow"
        "○ release notes"
    )
    SESSION_HEADERS=()
    BROKEN_START=-1
    NAV_SEARCH_QUERY=""
    NAV_SEARCH_MSG=""
    set_nav_selected "tower_a"
}

teardown() {
    teardown_test_env
}

@test "match: case-insensitive, ignores colour codes and the spinner placeholder" {
    source "$NAV" 2>/dev/null || true
    _fixture
    _search_row_matches 1 "login"
    _search_row_matches 1 "FIX THE LOGIN"
    _search_row_matches 3 "refactor login"
    ! _search_row_matches 2 "login"
    ! _search_row_matches 3 "SPIN"
    # a project row matches on the name its header shows
    _search_row_matches 0 "alpha"
}

@test "find: next starts after the cursor, wraps, and finds the cursor row last" {
    source "$NAV" 2>/dev/null || true
    _fixture
    _search_find "login" 1 next
    [ "$NAV_SEARCH_HIT" -eq 3 ]
    _search_find "login" 3 next
    [ "$NAV_SEARCH_HIT" -eq 1 ]
    _search_find "docs" 2 next
    [ "$NAV_SEARCH_HIT" -eq 2 ]
}

@test "find: prev walks backwards and wraps" {
    source "$NAV" 2>/dev/null || true
    _fixture
    _search_find "login" 1 prev
    [ "$NAV_SEARCH_HIT" -eq 3 ]
    _search_find "o" 0 prev
    [ "$NAV_SEARCH_HIT" -eq 4 ]
}

@test "find: no match leaves HIT at -1, and an empty list is not an error loop" {
    source "$NAV" 2>/dev/null || true
    _fixture
    run _search_find "zzz" 1 next
    [ "$status" -ne 0 ]
    _search_find "zzz" 1 next || true
    [ "$NAV_SEARCH_HIT" -eq -1 ]
    SESSION_IDS=()
    SESSION_DISPLAYS=()
    _search_find "x" 0 next || true
    [ "$NAV_SEARCH_HIT" -eq -1 ]
}

@test "step: n/N move the cursor and the selection file together" {
    source "$NAV" 2>/dev/null || true
    _fixture
    NAV_SEARCH_QUERY="login"
    search_step next 1
    [ "$NAV_NEW_INDEX" -eq 3 ]
    [ "$(get_nav_selected)" = "tower_c" ]
    search_step prev 3
    [ "$NAV_NEW_INDEX" -eq 1 ]
    [ "$(get_nav_selected)" = "tower_a" ]
}

@test "step: no match keeps the cursor and says so" {
    source "$NAV" 2>/dev/null || true
    _fixture
    NAV_SEARCH_QUERY="zzz"
    search_step next 2
    [ "$NAV_NEW_INDEX" -eq 2 ]
    [ "$NAV_SEARCH_MSG" = "no match" ]
    [ "$(get_nav_selected)" = "tower_a" ]
}

@test "prompt: typing jumps to the first match, Enter commits the query" {
    source "$NAV" 2>/dev/null || true
    _fixture
    search_prompt 1 >/dev/null < <(printf 'notes\n')
    [ "$NAV_NEW_INDEX" -eq 4 ]
    [ "$NAV_SEARCH_QUERY" = "notes" ]
    [ "$NAV_SEARCH_PROMPT" -eq 0 ]
    [ "$(get_nav_selected)" = "tower_d" ]
}

@test "prompt: Esc puts the cursor and selection back and keeps no query" {
    source "$NAV" 2>/dev/null || true
    _fixture
    search_prompt 1 >/dev/null < <(printf 'notes\033')
    [ "$NAV_NEW_INDEX" -eq 1 ]
    [ -z "$NAV_SEARCH_QUERY" ]
    [ "$(get_nav_selected)" = "tower_a" ]
}

@test "prompt: backspace edits the query; backspace on empty cancels" {
    source "$NAV" 2>/dev/null || true
    _fixture
    search_prompt 1 >/dev/null < <(printf 'docx\x7fs\n')
    [ "$NAV_SEARCH_QUERY" = "docs" ]
    [ "$NAV_NEW_INDEX" -eq 2 ]
    NAV_SEARCH_QUERY=""
    NAV_SEARCH_MSG=""
    search_prompt 1 >/dev/null < <(printf 'w\x7f\x7f')
    [ -z "$NAV_SEARCH_QUERY" ]
    [ "$NAV_NEW_INDEX" -eq 1 ]
}

@test "prompt: an arrow key sequence does not leak into the query" {
    source "$NAV" 2>/dev/null || true
    _fixture
    search_prompt 1 >/dev/null < <(printf 'do\033[Bcs\n')
    [ "$NAV_SEARCH_QUERY" = "docs" ]
}

@test "prompt: long sequences (Delete, Home, Ctrl-arrow) do not leak either" {
    source "$NAV" 2>/dev/null || true
    _fixture
    search_prompt 1 >/dev/null < <(printf 'do\033[3~\033[1~\033[1;5Ccs\n')
    [ "$NAV_SEARCH_QUERY" = "docs" ]
}

@test "escape: reads a whole sequence, and nothing for a lone Esc" {
    source "$NAV" 2>/dev/null || true
    nav_read_escape < <(printf '[1;5Dx')
    [ "$NAV_ESC_SEQ" = "[1;5D" ]
    nav_read_escape < <(printf '[A')
    [ "$NAV_ESC_SEQ" = "[A" ]
    nav_read_escape < <(printf 'OB')
    [ "$NAV_ESC_SEQ" = "OB" ]
    nav_read_escape < /dev/null
    [ -z "$NAV_ESC_SEQ" ]
}

@test "loop: Ctrl-Left in the list does not leave a stray D for the delete key" {
    local src="$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh"
    ! grep -q 'read -rsn2' "$src"
    grep -q 'nav_read_escape' "$src"
}

@test "match: no subshell per row (search runs every frame)" {
    ! grep -n '\$(_strip_ansi' "$PROJECT_ROOT/tmux-plugin/lib/nav/nav-search.sh"
}

@test "prompt: empty Enter turns search off" {
    source "$NAV" 2>/dev/null || true
    _fixture
    NAV_SEARCH_QUERY="login"
    search_prompt 1 >/dev/null < <(printf '\n')
    [ -z "$NAV_SEARCH_QUERY" ]
}

@test "prompt: committing a query with no match flags it and stays put" {
    source "$NAV" 2>/dev/null || true
    _fixture
    search_prompt 2 >/dev/null < <(printf 'zzz\n')
    [ "$NAV_NEW_INDEX" -eq 2 ]
    [ "$NAV_SEARCH_MSG" = "no match" ]
}

@test "step: n with no previous search moves nothing and says so" {
    source "$NAV" 2>/dev/null || true
    _fixture
    search_step next 2
    [ "$NAV_NEW_INDEX" -eq 2 ]
    [ "$NAV_SEARCH_MSG" = "no previous search" ]
    [ "$(get_nav_selected)" = "tower_a" ]
    run render_list 2
    [[ "$output" == *"no previous search"* ]]
}

@test "render: key list always in the footer; search position on the header line" {
    source "$NAV" 2>/dev/null || true
    _fixture
    run render_list 1
    [[ "$output" == *"/:find a:add"* ]]
    [[ "$output" == *"A:dir"* ]]
    [[ "$output" != *"/login"* ]]
    NAV_SEARCH_QUERY="login"
    run render_list 3
    local header
    header=$(printf '%s' "$output" | head -1)
    [[ "$header" == *"Sessions"*"/login [2/2]"* ]]
    [[ "$output" == *"a:add"* ]]
    NAV_SEARCH_QUERY="zzz"
    run render_list 1
    [[ "$output" == *"[no match]"* ]]
}

@test "render: while / is open the footer is the prompt line" {
    source "$NAV" 2>/dev/null || true
    _fixture
    NAV_SEARCH_PROMPT=1
    NAV_SEARCH_INPUT="log"
    run render_list 1
    [[ "$output" == *"/log▏"* ]]
    [[ "$output" != *"a:add"* ]]
}

@test "footer: the normal key list fits in 80 cells" {
    source "$NAV" 2>/dev/null || true
    _fixture
    local line
    line=$(grep -o 'j/k:nav[^$]*q:quit' "$PROJECT_ROOT/tmux-plugin/lib/nav/nav-render.sh")
    [ "$(str_display_width "$line")" -le 80 ]
}

@test "loop: / and n/N are handled before the project-row keys, unconditionally" {
    local src="$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh"
    local slash nn proj
    slash=$(grep -n 'search_prompt "\$selected_index"' "$src" | cut -d: -f1)
    nn=$(grep -n 'search_step next' "$src" | cut -d: -f1)
    proj=$(grep -n 'handle_project_key "\$key"' "$src" | cut -d: -f1)
    [ -n "$slash" ] && [ -n "$nn" ] && [ -n "$proj" ]
    [ "$slash" -lt "$proj" ]
    [ "$nn" -lt "$proj" ]
    grep -q 'if \[\[ "\$key" == n || "\$key" == N \]\]; then' "$src"
}

@test "loop: add and new-in-dir live on a and A, not n and N" {
    local src="$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh"
    run sed -n '/^                a)$/,/;;/p' "$src"
    [[ "$output" == *add_session_inline* ]]
    run sed -n '/^                A)$/,/;;/p' "$src"
    [[ "$output" == *new_session_pick_dir* ]]
    ! grep -qE '^                (n|N)\)$' "$src"
}

@test "render: on a narrow pane the wrapped header and footer still fit, so the search note stays on screen" {
    source "$NAV" 2>/dev/null || true
    _fixture
    TOWER_TERM_COLS=40
    TOWER_TERM_LINES=12
    local i
    for i in $(seq 1 30); do
        SESSION_IDS+=("tower_x$i")
        SESSION_DISPLAYS+=("○ filler session $i")
    done
    NAV_SEARCH_QUERY="a-rather-long-query-that-matches-nothing"
    run render_list 1
    # Count the screen rows the frame really takes, wrapping included.
    local rows=0 line w
    while IFS= read -r line; do
        _strip_ansi_into "$line"
        line="${NAV_STRIPPED//$'\033[K'/}"
        w=$(str_display_width "$line")
        rows=$((rows + (w <= 40 ? 1 : (w + 39) / 40)))
    done < <(printf '%s\n' "$output" | sed -E $'s/\033\\[\\?25l//; s/\033\\[H//; s/\033\\[J//')
    [ "$rows" -le 12 ]
    [[ "$(printf '%s' "$output" | head -1)" == *"[no match]"* ]]
}
