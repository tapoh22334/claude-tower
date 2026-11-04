#!/usr/bin/env bats
# Navigator key set after value/003-nav-keys: Enter and D are the only keys
# that read the row, `f` is the vimium-style label jump, `c` copies, and the
# help / footer list the keys the loop really handles.

load 'test_helper'

NAV="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# The nav files `declare -a` their arrays, which is local to whichever
# function sources them — so each test sources navigator-list.sh in its own
# body and then calls this to seat the list: three projects, the last one
# followed by an unrecoverable row.
_fixture() {
    signal_view_update_async() { :; }
    _flush_pending_view_signal() { :; }
    TOWER_TERM_LINES=30
    TOWER_TERM_COLS=80
    tput() { return 1; }
    SESSION_IDS=("dir:/p/alpha" "tower_a1" "tower_a2" "dir:/p/beta" "tower_b1" "dir:/p/gamma" "tower_c1" "tower_c2" "tower_dead")
    SESSION_DISPLAYS=("alpha ──" "a one" "a two" "beta ──" "b one" "gamma ──" "c one" "c two" "✗ dead one")
    SESSION_DIRS=("/p/alpha" "/p/alpha" "/p/alpha" "/p/beta" "/p/beta" "/p/gamma" "/p/gamma" "/p/gamma" "")
    SESSION_HEADERS=()
    BROKEN_START=8
    NAV_SEARCH_QUERY=""
    NAV_SEARCH_MSG=""
    set_nav_selected "tower_a1"
}

_labels() { printf '%s,' "${NAV_JUMP_LABELS[@]}"; }

# ----------------------------------------------------------------------------
# f: labels
# ----------------------------------------------------------------------------

@test "jump: a project row is its letter plus a, its sessions the letter plus b c..., unrecoverable none" {
    source "$NAV"
    _fixture
    _jump_assign_labels
    [ "$(_labels)" = "aa,ab,ac,ba,bb,ca,cb,cc,," ]
}

@test "jump: labels stop after z, for projects and for sessions in a project" {
    source "$NAV"
    _fixture
    local i
    SESSION_IDS=()
    for ((i = 0; i < 27; i++)); do SESSION_IDS+=("dir:/p/$i"); done
    SESSION_IDS+=("tower_x")
    BROKEN_START=-1
    _jump_assign_labels
    [ "${NAV_JUMP_LABELS[25]}" = "za" ]
    [ -z "${NAV_JUMP_LABELS[26]}" ]
    # the session under the unlabelled 27th project has no label either
    [ -z "${NAV_JUMP_LABELS[27]}" ]

    SESSION_IDS=("dir:/p/one")
    for ((i = 0; i < 27; i++)); do SESSION_IDS+=("tower_s$i"); done
    _jump_assign_labels
    # a is the project row's, so 25 sessions get b..z
    [ "${NAV_JUMP_LABELS[25]}" = "az" ]
    [ -z "${NAV_JUMP_LABELS[26]}" ]
}

@test "jump: a list with no project row has nothing to label" {
    source "$NAV"
    _fixture
    SESSION_IDS=()
    BROKEN_START=-1
    run _jump_assign_labels
    [ "$status" -eq 1 ]
}

@test "jump: render shows the labels left of the rows, and the first letter keeps only that project's" {
    source "$NAV"
    _fixture
    _jump_assign_labels
    NAV_JUMP_ACTIVE=1
    NAV_JUMP_PREFIX=""
    local out
    out=$(render_list 1 | _strip_ansi_str "$(cat)")
    [[ "$out" == *"aa alpha"* ]]
    [[ "$out" == *"cb   c one"* ]]
    [[ "$out" == *"jump:"* ]]
    NAV_JUMP_PREFIX="c"
    out=$(render_list 1 | _strip_ansi_str "$(cat)")
    [[ "$out" != *"ab   a one"* ]]
    [[ "$out" == *"   alpha"* ]]
    [[ "$out" == *"cc   c two"* ]]
}

@test "jump: rows with right-aligned marks still fit the width with the label column" {
    source "$NAV"
    _fixture
    local row line
    row=$(_compose_row "▶" "a session with marks" "⚙2 •")
    SESSION_DISPLAYS[1]="$row"
    SESSION_DISPLAYS[6]="$row"
    _jump_assign_labels
    NAV_JUMP_ACTIVE=1
    NAV_JUMP_PREFIX=""
    # without the label column the row fills the content width exactly
    [ "$(str_display_width "  $(_strip_ansi_str "$row")")" -eq "$(_content_width)" ]
    while IFS= read -r line; do
        line=$(_strip_ansi_str "${line//$'\033[K'/}")
        [ "$(str_display_width "$line")" -le "$(_content_width)" ] || {
            echo "too wide: [$line]"
            return 1
        }
    done < <(render_list 1)
    [[ "$(render_list 1 | _strip_ansi_str "$(cat)")" == *"cb   ▶ a session with marks"*"⚙2 •"* ]]
}

@test "jump: f c b lands on the third project's first session and clears the labels" {
    source "$NAV"
    _fixture
    jump_prompt 1 >/dev/null < <(printf 'cb')
    [ "$NAV_NEW_INDEX" -eq 6 ]
    [ "$(get_nav_selected)" = "tower_c1" ]
    [ -z "$NAV_JUMP_ACTIVE" ]
    [ -z "$NAV_JUMP_PREFIX" ]
}

@test "jump: the project row's two-letter label lands on it" {
    source "$NAV"
    _fixture
    jump_prompt 1 >/dev/null < <(printf 'ba')
    [ "$NAV_NEW_INDEX" -eq 3 ]
    [ "$(get_nav_selected)" = "dir:/p/beta" ]
}

@test "jump: Esc, a letter that labels nothing, or a bad second letter leave the cursor where it was" {
    source "$NAV"
    _fixture
    local keys
    for keys in $'\033' 'z' 'cz' $'\n' $'c\033' $'c\n'; do
        set_nav_selected "tower_a1"
        jump_prompt 1 >/dev/null < <(printf '%s' "$keys")
        [ "$NAV_NEW_INDEX" -eq 1 ]
        [ "$(get_nav_selected)" = "tower_a1" ]
        [ -z "$NAV_JUMP_ACTIVE" ]
    done
}

@test "jump: a row that left the list while the labels were up is not landed on" {
    source "$NAV"
    _fixture
    _jump_assign_labels
    NAV_NEW_INDEX=1
    SESSION_IDS=("dir:/p/alpha" "tower_a1" "tower_a2" "dir:/p/beta" "tower_b1" "dir:/p/gamma" "tower_c2")
    _jump_land "cb"
    [ "$NAV_NEW_INDEX" -eq 1 ]
    [ "$(get_nav_selected)" = "tower_a1" ]
    # the label still means the row it named when f was pressed
    _jump_land "cc"
    [ "$NAV_NEW_INDEX" -eq 6 ]
    [ "$(get_nav_selected)" = "tower_c2" ]
}

@test "jump: with no project row f does not enter the mode or read a key" {
    source "$NAV"
    _fixture
    SESSION_IDS=()
    BROKEN_START=-1
    local rest
    rest=$( { jump_prompt 0 >/dev/null; IFS= read -rsn1 k; printf '%s' "$k"; } < <(printf 'q'))
    [ "$rest" = "q" ]
    [ -z "$NAV_JUMP_ACTIVE" ]
}

# ----------------------------------------------------------------------------
# Key set
# ----------------------------------------------------------------------------

@test "keys: a project row reads only Enter and D; every other key goes to the ordinary handler" {
    source "$NAV"
    _fixture
    local k
    # i included: the loop turns it into Enter before this is reached
    for k in a c f t w $'\t' j k g G '?' q i r A; do
        run handle_project_key "$k" /p/alpha 0
        [ "$status" -eq 1 ]
    done
}

# The labels of the loop's key case, one per line, read from the source
# (declare -f re-indents the body). The key case sits at 16 spaces.
_loop_case_keys() {
    awk '/^main_loop\(\)/,/^}/' "$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh" |
        grep -oE '^ {16}[^ ()#]+( \| [^ ()]+)*\)' | tr -d ' )' | tr '|' '\n'
}

# set -e does not stop on a failing `! cmd`; these fail the test properly.
_absent() { if grep -qxE "$1" <<<"$2"; then return 1; fi; }
_undefined() { if declare -f "$1" >/dev/null; then return 1; fi; }

@test "keys: the loop has no r or A, reads i as Enter, and handles c; f and / go to their prompts" {
    source "$NAV"
    local keys
    keys=$(_loop_case_keys)
    _absent 'i|r|A' "$keys"
    # ...and before anything dispatches on the key, so a project row gets it
    # as Enter (new session there) rather than as a session row's open
    local src="$PROJECT_ROOT/tmux-plugin/lib/nav/nav-loop.sh" i_at first_use
    i_at=$(grep -nE '^ +\[\[ "\$key" == i \]\] && key=""$' "$src" | cut -d: -f1)
    first_use=$(grep -nE 'search_prompt "\$selected_index"|handle_project_key "\$key"' "$src" | head -1 | cut -d: -f1)
    [ -n "$i_at" ] && [ -n "$first_use" ]
    [ "$i_at" -lt "$first_use" ]
    grep -qx 'c' <<<"$keys"
    grep -qx 'D' <<<"$keys"
    declare -f main_loop | grep -q 'jump_prompt'
    declare -f main_loop | grep -q 'search_prompt'
    _undefined fork_session_here
    _undefined new_session_pick_dir
}

@test "keys: help lists all 18 keys; the footer names only those keys and fits 80 cells" {
    source "$NAV"
    _fixture
    local help footer k
    help=$(show_help </dev/null 2>/dev/null || true)
    for k in "j / " "k / " "g / G" "/ text" "n / N" "f x y" "Enter / i" "  a  " "  c  " "  D  " "Tab / t" "  w  " "?" "q  Quit"; do
        [[ "$help" == *"$k"* ]] || { echo "help lacks [$k]"; return 1; }
    done
    [[ "$help" != *"Resume selected"* ]]
    [ "$(printf '%s\n' "$help" | wc -l)" -lt 24 ]
    footer=$(render_list 1 | tail -n 1)
    footer=$(_strip_ansi_str "${footer//$'\033[K'/}")
    [ "$(str_display_width "$footer")" -le 80 ]
    for k in $footer; do
        case "${k%%:*}" in
            j/k | ↵ | / | f | a | c | D | t | w | '?' | q) ;;
            *) echo "footer key not in the set: $k"; return 1 ;;
        esac
    done
}

# ----------------------------------------------------------------------------
# a: default dir
# ----------------------------------------------------------------------------

@test "a: the new session's place defaults to the cursor row's project, else the caller cwd" {
    source "$NAV"
    _fixture
    local d="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$d"
    get_caller_cwd() { echo /caller; }
    _session_dir() { [[ "$1" == tower_a1 ]] && echo "$d"; }
    set_nav_selected "dir:$d"
    [ "$(_add_default_dir)" = "$d" ]
    set_nav_selected "tower_a1"
    [ "$(_add_default_dir)" = "$d" ]
    set_nav_selected "tower_b1"
    [ "$(_add_default_dir)" = "/caller" ]
    set_nav_selected "dir:/no/such/dir"
    [ "$(_add_default_dir)" = "/caller" ]
}

# ----------------------------------------------------------------------------
# c: the claude command line
# ----------------------------------------------------------------------------

@test "copy: start_claude_session copy mode resumes the source under a new id with --fork-session" {
    local sent=""
    session_tmux() {
        case "$1" in
            has-session) return 1 ;;
            send-keys) [[ "$4" == "C-l" ]] || sent="$4" ;;
        esac
        return 0
    }
    _wait_for_shell_ready() { :; }
    register_project() { :; }
    start_claude_session "tower_new-id" "$BATS_TEST_TMPDIR" copy "" "src-claude-id" >/dev/null
    [[ "$sent" == *" --resume src-claude-id --fork-session --session-id new-id" ]]
}

# ----------------------------------------------------------------------------
# Enter: resume only the row on screen
# ----------------------------------------------------------------------------

@test "enter: a selected file that names another row only focuses, never resumes" {
    source "$NAV"
    _fixture
    local resumed="" focused=""
    restore_selected() { resumed=1; }
    focus_view() { focused=1; }
    session_tmux() { return 1; }
    has_metadata() { return 0; }
    get_display_state() { echo dormant; }
    set_nav_selected "tower_b1"
    open_selected "tower_a1"
    [ -z "$resumed" ]
    [ -n "$focused" ]
    [ -z "$NAV_OPEN_RESUMED" ]
    open_selected "tower_b1"
    [ -n "$resumed" ]
}

# ----------------------------------------------------------------------------
# Enter on a project row: the new session appears in the list (#113)
# ----------------------------------------------------------------------------

# A project group in a real directory, and a session-add.sh stand-in that
# records what the list showed while it ran. $1 is the stand-in's exit code.
_creating_fixture() {
    signal_view_update() { :; }
    signal_view_update_async() { :; }
    _flush_pending_view_signal() { :; }
    sleep() { :; }
    TOWER_TERM_LINES=30
    TOWER_TERM_COLS=80
    tput() { return 1; }
    PROJ="$BATS_TEST_TMPDIR/proj"
    mkdir -p "$PROJ"
    SESSION_IDS=("dir:$PROJ" "tower_00000000-0000-0000-0000-000000000001")
    SESSION_DISPLAYS=("proj ──" "existing")
    SESSION_DIRS=("$PROJ" "$PROJ")
    SESSION_HEADERS=("" "")
    BROKEN_START=-1
    set_nav_selected "dir:$PROJ"
    SCRIPT_DIR="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$SCRIPT_DIR"
    cat >"$SCRIPT_DIR/session-add.sh" <<STUB
#!/usr/bin/env bash
id=""
while [[ \$# -gt 0 ]]; do [[ "\$1" == --id ]] && id="\$2"; shift; done
echo "args-id:\$id" >>"$BATS_TEST_TMPDIR/calls"
if [[ $1 -ne 0 ]]; then echo "Failed to create tmux session" >&2; exit $1; fi
echo "Success: Session started" >&2
echo "tower_\$id"
STUB
    chmod +x "$SCRIPT_DIR/session-add.sh"
    # What the screen held: every frame drawn, and any clear.
    clear() { echo CLEAR >>"$BATS_TEST_TMPDIR/screen"; }
    render_list() {
        local i
        for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
            echo "$i|${SESSION_IDS[$i]}|$(_strip_ansi_str "${SESSION_DISPLAYS[$i]}")"
        done >>"$BATS_TEST_TMPDIR/screen"
        echo "selected=$1" >>"$BATS_TEST_TMPDIR/screen"
    }
}

@test "project Enter: the list stays up with a creating row, which becomes the started session" {
    source "$NAV"
    _creating_fixture 0
    new_session_in_project "$PROJ" >/dev/null 2>&1
    # never cleared; the frame drawn while starting already held the row
    ! grep -q CLEAR "$BATS_TEST_TMPDIR/screen"
    grep -q "creating…" "$BATS_TEST_TMPDIR/screen"
    # the id handed to session-add is the id of the creating row
    local id
    id=$(sed -n 's/^args-id://p' "$BATS_TEST_TMPDIR/calls")
    [[ "$id" =~ ^[0-9a-f-]{36}$ ]]
    grep -q "|tower_$id|.*creating…" "$BATS_TEST_TMPDIR/screen"
    # the cursor was drawn on that row
    local row
    row=$(grep "|tower_$id|" "$BATS_TEST_TMPDIR/screen" | head -1 | cut -d'|' -f1)
    grep -qx "selected=$row" "$BATS_TEST_TMPDIR/screen"
    # afterwards: the same row, started (◐ and the id), selected
    [ "$(get_nav_selected)" = "tower_$id" ]
    local i found=""
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        [[ "${SESSION_IDS[$i]}" == "tower_$id" ]] && found="$(_strip_ansi_str "${SESSION_DISPLAYS[$i]}")"
    done
    [[ "$found" == *"◐"* ]]
    [[ "$found" == *"${id:0:7}"* ]]
    [[ "$found" != *"creating"* ]]
    [ "${#SESSION_IDS[@]}" -eq 3 ]
}

@test "project Enter: a failed start takes the creating row away and says why" {
    source "$NAV"
    _creating_fixture 1
    local out
    out=$(new_session_in_project "$PROJ" 2>/dev/null; printf '%s,' "${#SESSION_IDS[@]}")
    [[ "$out" == *"Failed to create tmux session"* ]]
    ! grep -q CLEAR "$BATS_TEST_TMPDIR/screen"
    grep -q "creating…" "$BATS_TEST_TMPDIR/screen"
    new_session_in_project "$PROJ" >/dev/null 2>&1
    [ "${#SESSION_IDS[@]}" -eq 2 ]
    [ "$(get_nav_selected)" = "dir:$PROJ" ]
}
