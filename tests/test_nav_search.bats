#!/usr/bin/env bats
# Navigator `/` search (#82): matching, n/N stepping, the prompt sub-loop,
# the footer that says n/N have changed meaning, and the loop wiring.

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
    search_clear
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
    search_clear
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

@test "footer: shows the key list normally and the search state while searching" {
    source "$NAV" 2>/dev/null || true
    _fixture
    run render_list 1
    [[ "$output" == *"/:find"* ]]
    [[ "$output" == *"n:add"* ]]
    NAV_SEARCH_QUERY="login"
    run render_list 3
    [[ "$output" == *"/login [2/2]"* ]]
    [[ "$output" == *"n/N:next/prev esc:clear"* ]]
    [[ "$output" != *"n:add"* ]]
    NAV_SEARCH_QUERY="zzz"
    run render_list 1
    [[ "$output" == *"[no match]"* ]]
}

@test "footer: the normal key list fits in 80 cells" {
    source "$NAV" 2>/dev/null || true
    _fixture
    local line
    line=$(grep -o 'j/k:nav[^$]*q:quit' "$PROJECT_ROOT/tmux-plugin/lib/nav/nav-render.sh")
    [ "$(str_display_width "$line")" -le 80 ]
}

@test "loop: / and active-search n/N are handled before the project-row keys" {
    local src="$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh"
    local slash nn proj
    slash=$(grep -n 'search_prompt "\$selected_index"' "$src" | cut -d: -f1)
    nn=$(grep -n 'search_step next' "$src" | cut -d: -f1)
    proj=$(grep -n 'handle_project_key "\$key"' "$src" | cut -d: -f1)
    [ -n "$slash" ] && [ -n "$nn" ] && [ -n "$proj" ]
    [ "$slash" -lt "$proj" ]
    [ "$nn" -lt "$proj" ]
    # n/N fall through to add/new-dir when no query is active
    grep -q 'if \[\[ -n "\$NAV_SEARCH_QUERY" && ( "\$key" == n' "$src"
}

@test "loop: a lone Esc in the list clears the search" {
    local src="$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh"
    run sed -n "/'') # A lone Esc clears the search./,/;;/p" "$src"
    [[ "$output" == *"search_clear"* ]]
}
