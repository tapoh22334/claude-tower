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
    skip "requires PATH shadowing to force/omit uuidgen — see session-add.sh:18-19"
}

@test "generate_uuid: falls back to /proc/sys/kernel/random/uuid when uuidgen is missing" {
    skip "requires PATH shadowing to hide uuidgen while keeping /proc readable — see session-add.sh:20-21"
}

@test "generate_uuid: calls handle_error and returns 1 when neither uuidgen nor /proc source is available" {
    skip "requires PATH shadowing plus /proc/sys/kernel/random/uuid unreadable — see session-add.sh:22-24"
}

# ============================================================================
# format_candidate_lines(): session-add.sh:29 — id\tmtime\tcwd -> display line
# ============================================================================

@test "format_candidate_lines: abbreviates HOME-prefixed cwd to ~" {
    run bash -c "source '$PROJECT_ROOT/tmux-plugin/lib/common.sh' 2>/dev/null; source <(sed -n '17,40p' '$SESSION_ADD'); printf '1234567-uuid\t$(date +%s)\t$HOME/foo\n' | format_candidate_lines"
    [ "$status" -eq 0 ]
    [[ "$output" == *"~/foo"* ]]
}

@test "format_candidate_lines: leaves non-HOME cwd unabbreviated" {
    skip "see session-add.sh:35-37 — assert /tmp/foo passes through unchanged"
}

@test "format_candidate_lines: truncates id to 7 chars for the short id column" {
    skip "see session-add.sh:32 — assert 40-char id is truncated to 7"
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

@test "resolve_picked_id: resolves a unique short-id prefix to the full id" {
    skip "call resolve_picked_id directly by sourcing session-add.sh functions in isolation (extract lines 82-97) — see session-add.sh:82-97"
}

@test "resolve_picked_id: returns 1 and calls handle_error on ambiguous short-id prefix match" {
    skip "two candidate ids sharing the same 7-char prefix — see session-add.sh:87-91"
}

@test "resolve_picked_id: returns 1 when no candidate matches the picked short id" {
    skip "see session-add.sh:95"
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
source <(sed -n '17,153p' "$SESSION_ADD")
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
    run bash -c "source '$PROJECT_ROOT/tmux-plugin/lib/common.sh' 2>/dev/null; source <(sed -n '155,175p' '$SESSION_ADD'); add_existing_session 'not-a-uuid'"
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
        source <(sed -n '17,175p' '$SESSION_ADD')
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
    skip "requires stubbing run_picker/start_claude_session end-to-end — see session-add.sh:189-190"
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
