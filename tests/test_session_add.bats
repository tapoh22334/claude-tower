#!/usr/bin/env bats
# Coverage gap: tmux-plugin/scripts/session-add.sh has zero test references
# anywhere in the suite (9 functions, 39 error-handling branches, the only
# git-worktree creation logic in the codebase). See coverage analysis for
# full function inventory.
#
# session-add.sh calls `main "$@"` unconditionally at file scope (line 201),
# so it cannot be sourced for in-process unit testing without side effects —
# all tests here invoke it as a subprocess via $PROJECT_ROOT.

load 'test_helper'

setup() {
    bats_require_minimum_version 1.5.0
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

SESSION_ADD="$PROJECT_ROOT/tmux-plugin/scripts/session-add.sh"

# ============================================================================
# --print-id stdout purity (Fix 1): start_claude_session's handle_success
# writes ANSI text to stdout; add_existing_session/start_new_session must
# redirect it to stderr so callers capturing `$(session-add.sh --print-id)`
# (e.g. navigator-list.sh's add_session_inline) get ONLY the tower_<uuid>
# line, not "Success: ..." text prepended/mixed in.
#
# A PATH-shadowed fake `tmux` stubs has-session (exit 1: never "already
# running"), new-session/send-keys/kill-session/display-message (exit 0),
# and capture-pane (prints a shell-prompt-like string so
# _wait_for_shell_ready's regex matches immediately).
# ============================================================================

setup_fake_tmux() {
    mkdir -p "$BATS_TEST_TMPDIR/fakebin"
    cat > "$BATS_TEST_TMPDIR/fakebin/tmux" <<'STUB'
#!/usr/bin/env bash
# Real invocations look like: tmux -L <socket> <subcommand> ...
sub=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -L) shift 2; continue ;;
        *) sub="$1"; break ;;
    esac
done
case "$sub" in
    has-session) exit 1 ;;
    capture-pane) echo '$ '; exit 0 ;;
    *) exit 0 ;;
esac
STUB
    chmod +x "$BATS_TEST_TMPDIR/fakebin/tmux"
    export PATH="$BATS_TEST_TMPDIR/fakebin:$PATH"
}

# ============================================================================
# generate_uuid(): session-add.sh:17 — uuidgen / /proc fallback / error chain
# ============================================================================

@test "generate_uuid: uses uuidgen when available and lowercases output" {
    mkdir -p "$BATS_TEST_TMPDIR/fakebin"
    cat > "$BATS_TEST_TMPDIR/fakebin/uuidgen" <<'STUB'
#!/usr/bin/env bash
echo "ABCDEF01-2345-6789-ABCD-EF0123456789"
STUB
    chmod +x "$BATS_TEST_TMPDIR/fakebin/uuidgen"

    run bash -c "
        export PATH='$BATS_TEST_TMPDIR/fakebin:$PATH'
        source '$PROJECT_ROOT/tmux-plugin/lib/common.sh'
        source <(sed -n '17,26p' '$SESSION_ADD')
        generate_uuid
    "
    [ "$status" -eq 0 ]
    [ "$output" = "abcdef01-2345-6789-abcd-ef0123456789" ]
}

# Build a PATH containing symlinks to every tool needed to source common.sh
# and run generate_uuid, EXCEPT uuidgen (which is deliberately omitted so
# `command -v uuidgen` fails and the /proc fallback branch is exercised).
setup_path_without_uuidgen() {
    local dir="$BATS_TEST_TMPDIR/fakebin_no_uuidgen"
    mkdir -p "$dir"
    local tool
    for tool in bash cat sed grep mkdir date tr basename dirname mktemp \
                sleep tput printf true false env; do
        local resolved
        resolved="$(command -v "$tool" 2>/dev/null)" || continue
        ln -sf "$resolved" "$dir/$tool"
    done
    echo "$dir"
}

@test "generate_uuid: falls back to /proc/sys/kernel/random/uuid when uuidgen is missing" {
    [[ -r /proc/sys/kernel/random/uuid ]] || skip "/proc/sys/kernel/random/uuid not available on this platform"

    local dir
    dir="$(setup_path_without_uuidgen)"
    run bash -c "
        export PATH='$dir'
        source '$PROJECT_ROOT/tmux-plugin/lib/common.sh'
        source <(sed -n '17,26p' '$SESSION_ADD')
        generate_uuid
    "
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f-]{36}$ ]]
}

@test "generate_uuid: calls handle_error and returns 1 when neither uuidgen nor /proc source is available" {
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        skip "cannot simulate missing /proc/sys/kernel/random/uuid on this platform without root"
    fi
    local dir
    dir="$(setup_path_without_uuidgen)"
    run bash -c "
        export PATH='$dir'
        source '$PROJECT_ROOT/tmux-plugin/lib/common.sh'
        source <(sed -n '17,26p' '$SESSION_ADD')
        generate_uuid
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot generate a UUID"* ]]
}

# ============================================================================
# format_candidate_lines(): session-add.sh:29 — id\tmtime\tcwd -> display line
# ============================================================================

# Extracts the function by name (not by line range) so edits elsewhere in
# session-add.sh don't silently break the extraction.
_run_format_candidate_lines() {
    local input="$1"
    run bash -c "
        export CLAUDE_HISTORY_FILE='$BATS_TEST_TMPDIR/history.jsonl'
        source '$PROJECT_ROOT/tmux-plugin/lib/common.sh' 2>/dev/null
        eval \"\$(sed -n '/^format_candidate_lines()/,/^}/p' '$SESSION_ADD')\"
        printf '%b\n' '$input' | format_candidate_lines
    "
}

@test "format_candidate_lines: 4-char short id, cwd basename, title from history" {
    printf '%s\n' '{"display":"fix the login bug","pastedContents":{},"sessionId":"abcdefab-1111-4111-8111-111111111111"}' \
        > "$BATS_TEST_TMPDIR/history.jsonl"
    _run_format_candidate_lines "abcdefab-1111-4111-8111-111111111111\t$(date +%s)\t$HOME/projects/myproj"
    [ "$status" -eq 0 ]
    [[ "$output" == "abcd  "* ]]
    [[ "$output" == *"myproj"* ]]
    [[ "$output" == *"fix the login bug"* ]]
    # basename only — no full path, no ~ abbreviation
    [[ "$output" != *"projects/myproj"* ]]
}

@test "format_candidate_lines: session missing from history gets an empty title, line still renders" {
    : > "$BATS_TEST_TMPDIR/history.jsonl"
    _run_format_candidate_lines "abcdefab-2222-4222-8222-222222222222\t$(date +%s)\t/tmp/dir-b"
    [ "$status" -eq 0 ]
    [[ "$output" == "abcd  "* ]]
    [[ "$output" == *"dir-b"* ]]
    [[ "$output" == *"ago)"* ]]
}

@test "format_candidate_lines: long titles are truncated" {
    local long_title
    long_title=$(printf 'x%.0s' $(seq 1 80))
    printf '%s\n' "{\"display\":\"${long_title}\",\"sessionId\":\"abcdefab-3333-4333-8333-333333333333\"}" \
        > "$BATS_TEST_TMPDIR/history.jsonl"
    _run_format_candidate_lines "abcdefab-3333-4333-8333-333333333333\t$(date +%s)\t/tmp/dir-c"
    [ "$status" -eq 0 ]
    [[ "$output" != *"$long_title"* ]]
    [[ "$output" == *"xxxxx…"* ]]
}

@test "format_candidate_lines: history matches the exact session id, not another session's prompt" {
    {
        printf '%s\n' '{"display":"other session prompt","sessionId":"ffffffff-9999-4999-8999-999999999999"}'
        printf '%s\n' '{"display":"second prompt of mine","sessionId":"abcdefab-4444-4444-8444-444444444444"}'
    } > "$BATS_TEST_TMPDIR/history.jsonl"
    _run_format_candidate_lines "abcdefab-4444-4444-8444-444444444444\t$(date +%s)\t/tmp/dir-d"
    [ "$status" -eq 0 ]
    [[ "$output" == *"second prompt of mine"* ]]
    [[ "$output" != *"other session prompt"* ]]
}

# ============================================================================
# pick_with_numbers(): session-add.sh:43 — numbered fallback picker
# ============================================================================

@test "pick_with_numbers: valid numeric choice echoes the matching line" {
    skip "requires /dev/tty stdin injection — see session-add.sh:55; consider refactoring to accept an injectable fd for testability"
}

@test "pick_with_numbers: rejects non-numeric input and returns 1" {
    skip "requires /dev/tty stdin injection — see session-add.sh:56"
}

@test "pick_with_numbers: rejects out-of-range numeric input and returns 1" {
    skip "requires /dev/tty stdin injection — see session-add.sh:57 (choice=0 and choice=N+1 boundary cases)"
}

@test "pick_with_numbers: empty input (plain Enter) cancels and returns 1" {
    skip "requires /dev/tty stdin injection — see session-add.sh:55-56"
}

# ============================================================================
# run_picker(): session-add.sh:65 — TOWER_FINDER dispatch and fallback warning
# ============================================================================

@test "run_picker: uses fzf by default when fzf is on PATH" {
    skip "requires PATH shadowing with a fake fzf binary — see session-add.sh:66-69"
}

@test "run_picker: silently falls back to pick_with_numbers when default fzf is missing (no TOWER_FINDER set)" {
    skip "requires PATH shadowing to hide fzf while TOWER_FINDER is unset — see session-add.sh:70-75; must assert NO stderr warning per comment at :62-64"
}

@test "run_picker: warns loudly on stderr and falls back when user-set TOWER_FINDER binary is missing" {
    TOWER_FINDER="totally-not-a-real-finder --flag" run bash -c "echo '' | '$SESSION_ADD'"
    [[ "$output" == *"TOWER_FINDER command not found: totally-not-a-real-finder"* ]]
}

# ============================================================================
# resolve_picked_id(): session-add.sh:82 — short-id prefix resolution
# ============================================================================

# Resolution matches the picked line against the rendered lines by index —
# the short id is display-only, so even identical 4-char prefixes resolve
# correctly as long as the rendered lines differ.
# common.sh is already loaded by setup()'s source_common (handle_error).
_source_resolver() {
    eval "$(sed -n '/^resolve_picked_id()/,/^}/p' "$SESSION_ADD")"
}

@test "resolve_picked_id: resolves the picked rendered line to the id at the same index" {
    _source_resolver
    local candidates rendered
    candidates=$'aaaa1111-1111-4111-8111-111111111111\t100\t/tmp/a\naaaa2222-2222-4222-8222-222222222222\t200\t/tmp/b'
    rendered=$'aaaa  dir-a  first prompt  (2m ago)\naaaa  dir-b  other prompt  (5m ago)'
    run resolve_picked_id 'aaaa  dir-b  other prompt  (5m ago)' "$rendered" <<<"$candidates"
    [ "$status" -eq 0 ]
    [ "$output" = "aaaa2222-2222-4222-8222-222222222222" ]
}

@test "resolve_picked_id: identical short ids are fine when the rest of the line differs" {
    _source_resolver
    local candidates rendered
    candidates=$'aaaa1111-1111-4111-8111-111111111111\t100\t/tmp/a\naaaa1111-9999-4999-8999-999999999999\t200\t/tmp/a'
    rendered=$'aaaa  proj  fix login  (2m ago)\naaaa  proj  add tests  (5m ago)'
    run resolve_picked_id 'aaaa  proj  fix login  (2m ago)' "$rendered" <<<"$candidates"
    [ "$status" -eq 0 ]
    [ "$output" = "aaaa1111-1111-4111-8111-111111111111" ]
}

@test "resolve_picked_id: returns 1 on fully identical rendered lines instead of guessing" {
    _source_resolver
    local candidates rendered
    candidates=$'aaaa1111-1111-4111-8111-111111111111\t100\t/tmp/a\naaaa2222-2222-4222-8222-222222222222\t100\t/tmp/a'
    rendered=$'aaaa  proj  same  (2m ago)\naaaa  proj  same  (2m ago)'
    run resolve_picked_id 'aaaa  proj  same  (2m ago)' "$rendered" <<<"$candidates"
    [ "$status" -ne 0 ]
}

@test "resolve_picked_id: returns 1 when the picked line matches no rendered line" {
    _source_resolver
    local candidates rendered
    candidates=$'aaaa1111-1111-4111-8111-111111111111\t100\t/tmp/a'
    rendered=$'aaaa  proj  hello  (2m ago)'
    run resolve_picked_id 'bbbb  gone  stale line  (9m ago)' "$rendered" <<<"$candidates"
    [ "$status" -ne 0 ]
}

# ============================================================================
# prompt_new_directory(): session-add.sh:102 — default dir / worktree flow
# ============================================================================

@test "prompt_new_directory: empty input returns the default directory" {
    skip "requires /dev/tty stdin injection — see session-add.sh:107-109"
}

@test "prompt_new_directory: expands leading ~ to \$HOME" {
    skip "requires /dev/tty stdin injection — see session-add.sh:134"
}

@test "prompt_new_directory: '+' on a non-git-repo default dir rejects with 'Not a git repository'" {
    skip "requires /dev/tty stdin injection feeding '+' then repo path — see session-add.sh:116-118"
}

@test "prompt_new_directory: '+' with empty worktree path returns 1" {
    skip "requires /dev/tty stdin injection — see session-add.sh:121-122"
}

@test "prompt_new_directory: '+' derives default branch name tower/<basename> from worktree path" {
    skip "requires /dev/tty stdin injection plus a real git repo fixture — see session-add.sh:123-125"
}

@test "prompt_new_directory: '+' surfaces 'git worktree add failed' and returns 1 on git failure" {
    skip "requires a git repo fixture with a colliding branch/path to force worktree add failure — see session-add.sh:126-129"
}

@test "prompt_new_directory: '+' on success echoes the new worktree path" {
    skip "requires a real git repo fixture in \$BATS_TEST_TMPDIR — see session-add.sh:126-131"
}

# ============================================================================
# start_new_session(): session-add.sh:138 — new-session creation flow
# ============================================================================

@test "start_new_session: handle_error and return 1 when the resolved directory does not exist" {
    skip "requires /dev/tty stdin injection returning a nonexistent path — see session-add.sh:142-144"
}

@test "start_new_session: propagates failure from prompt_new_directory" {
    skip "requires /dev/tty EOF to make prompt_new_directory's read fail — see session-add.sh:141"
}

@test "start_new_session: propagates failure from generate_uuid" {
    skip "requires PATH shadowing to break generate_uuid entirely — see session-add.sh:148"
}

@test "start_new_session: propagates failure from start_claude_session without saving metadata" {
    skip "requires stubbing start_claude_session to fail — see session-add.sh:149-150 (assert save_metadata NOT called on failure)"
}

@test "start_new_session: saves metadata with the optional name and prints tower_<uuid> when --print-id is set" {
    setup_fake_tmux

    local dir="$BATS_TEST_TMPDIR/new-session-dir"
    mkdir -p "$dir"

    # prompt_new_directory reads default (blank -> $TOWER_ADD_DEFAULT_DIR),
    # then the optional name prompt (blank). Both /dev/tty reads need a real
    # pty, so drive the script through `script`.
    local script_out="$BATS_TEST_TMPDIR/out.log"
    local script_err="$BATS_TEST_TMPDIR/err.log"
    cat > "$BATS_TEST_TMPDIR/drive.sh" <<EOF
#!/usr/bin/env bash
export PATH="$PATH"
export CLAUDE_TOWER_METADATA_DIR="$CLAUDE_TOWER_METADATA_DIR"
export CLAUDE_PROJECTS_DIR="$CLAUDE_PROJECTS_DIR"
export TOWER_ADD_DEFAULT_DIR="$dir"
source "$PROJECT_ROOT/tmux-plugin/lib/common.sh"
# Anchor on function boundaries, not line numbers: everything from the
# sentinel down to (excluding) main(), so edits above don't shift the range.
source <(sed -n '/^NEW_SENTINEL=/,\$p' "$SESSION_ADD" | sed '/^main() {/,\$d')
PRINT_ID=1
start_new_session 1>"$script_out" 2>"$script_err"
EOF
    chmod +x "$BATS_TEST_TMPDIR/drive.sh"

    printf '\n\n' | script -qec "$BATS_TEST_TMPDIR/drive.sh" /dev/null >/dev/null

    run cat "$script_out"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^tower_[0-9a-f-]+$ ]]
    # handle_success's "Success: ..." text is correctly routed to stderr
    # (the fix), never mixed into the captured stdout id above.
    [[ "$(cat "$script_err")" == *"Success:"* ]]
}

# ============================================================================
# add_existing_session(): session-add.sh:155 — resume-existing flow
# ============================================================================

@test "add_existing_session: rejects a claude_id that is not a well-formed UUID" {
    run bash -c "source '$PROJECT_ROOT/tmux-plugin/lib/common.sh' 2>/dev/null; source <(sed -n '/^NEW_SENTINEL=/,\$p' '$SESSION_ADD' | sed '/^main() {/,\$d'); add_existing_session 'not-a-uuid'"
    [ "$status" -eq 1 ]
}

@test "add_existing_session: handle_error 'Transcript not found' when find_session_jsonl fails" {
    skip "requires a syntactically valid UUID with no matching jsonl fixture — see session-add.sh:162-165"
}

@test "add_existing_session: handle_error 'Directory not found' when transcript cwd is missing or nonexistent" {
    skip "requires create_mock_jsonl fixture with a cwd pointing at a nonexistent directory — see session-add.sh:167-169"
}

@test "add_existing_session: propagates failure from start_claude_session without saving metadata" {
    skip "requires stubbing start_claude_session to fail with a valid jsonl fixture — see session-add.sh:171-172"
}

@test "add_existing_session: saves metadata and prints tower_<claude_id> when --print-id is set" {
    setup_fake_tmux

    local uuid="11112222-3333-4444-5555-666677778888"
    create_mock_jsonl "testslug" "$uuid" "$PROJECT_ROOT" >/dev/null

    run --separate-stderr bash -c "
        source '$PROJECT_ROOT/tmux-plugin/lib/common.sh'
        source <(sed -n '/^NEW_SENTINEL=/,\$p' '$SESSION_ADD' | sed '/^main() {/,\$d')
        PRINT_ID=1
        add_existing_session '$uuid'
    "

    [ "$status" -eq 0 ]
    [ "$output" = "tower_${uuid}" ]
    [[ "$stderr" == *"Success:"* ]]
}

# ============================================================================
# main(): session-add.sh:177 — end-to-end dispatch ([new] vs existing pick)
# ============================================================================

@test "main: returns 1 when run_picker (via empty candidates and closed stdin) yields no selection" {
    run bash -c "echo -n '' | '$SESSION_ADD' </dev/null"
    [ "$status" -ne 0 ]
}

@test "main: dispatches to start_new_session when [new] sentinel is picked" {
    # pipefail regression test (first-run experience): with ZERO addable
    # candidates, main()'s picker pipeline used `[[ -n "$candidates" ]] &&
    # format_candidate_lines`, whose exit-1 (empty candidates) tripped
    # `set -o pipefail` and aborted the flow even on a valid [new] pick.
    # TOWER_FINDER="head -n1" is a non-interactive picker that selects the
    # first line (the [new] sentinel); CLAUDE_PROJECTS_DIR stays empty so
    # list_addable_sessions yields nothing.
    setup_fake_tmux

    local dir="$BATS_TEST_TMPDIR/new-session-dir"
    mkdir -p "$dir"

    local script_out="$BATS_TEST_TMPDIR/main_out.log"
    local script_err="$BATS_TEST_TMPDIR/main_err.log"
    cat > "$BATS_TEST_TMPDIR/main_drive.sh" <<EOF
#!/usr/bin/env bash
export PATH="$PATH"
export CLAUDE_TOWER_METADATA_DIR="$CLAUDE_TOWER_METADATA_DIR"
export CLAUDE_PROJECTS_DIR="$CLAUDE_PROJECTS_DIR"
export TOWER_ADD_DEFAULT_DIR="$dir"
export TOWER_FINDER="head -n1"
"$SESSION_ADD" --print-id 1>"$script_out" 2>"$script_err"
echo "EXIT:\$?" >>"$script_err"
EOF
    chmod +x "$BATS_TEST_TMPDIR/main_drive.sh"

    # start_new_session's /dev/tty prompts (directory default, blank name)
    # need a real pty, hence `script`.
    printf '\n\n' | script -qec "$BATS_TEST_TMPDIR/main_drive.sh" /dev/null >/dev/null

    run cat "$script_out"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^tower_[0-9a-f-]+$ ]]
    [[ "$(cat "$script_err")" == *"EXIT:0"* ]]
}

@test "main: handle_error 'Could not resolve selection' when resolve_picked_id fails for a non-[new] pick" {
    skip "requires forcing a picker return value with no matching candidate — see session-add.sh:192-196"
}

@test "main: dispatches to add_existing_session with the resolved claude_id on a normal pick" {
    skip "requires stubbing run_picker/resolve_picked_id/start_claude_session end-to-end — see session-add.sh:191-198"
}

@test "main: --print-id flag is recognized only as the first argument" {
    skip "see session-add.sh:13 — PRINT_ID only checks \${1:-}; assert second-position --print-id is NOT honored"
}

# ============================================================================
# Integration: the only git-worktree creation logic in the codebase is
# entirely untested end-to-end (prompt_new_directory '+' branch feeding
# start_new_session feeding start_claude_session).
# ============================================================================

@test "integration: '+' worktree flow creates a real worktree and registers a new tower session" {
    skip "needs a disposable git repo fixture under \$BATS_TEST_TMPDIR, full /dev/tty stdin script, and a live tmux server — exercises session-add.sh:111-131 + :138-152 together"
}
