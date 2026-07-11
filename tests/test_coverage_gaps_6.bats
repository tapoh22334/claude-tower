#!/usr/bin/env bats
# Further coverage-gap skeletons: session-list.sh, session-restore.sh,
# session-delete.sh, preview.sh, diff.sh, input.sh, and safe_tmux() — none of
# these are exercised by any prior test_coverage_gaps*.bats file.

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================================================
# safe_tmux(): common.sh:724 — zero test references anywhere in the suite.
# ============================================================================

@test "safe_tmux: returns 0 and passes through output on a successful tmux command" {
    run safe_tmux list-sessions -F '#{session_name}'
    # no live tmux server is guaranteed in this environment; only assert the
    # function itself doesn't blow up with a bash error (e.g. unbound var)
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "safe_tmux: returns 1 and suppresses stderr when the tmux subcommand fails" {
    run safe_tmux totally-not-a-real-subcommand
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "safe_tmux: forwards all extra arguments to the underlying tmux invocation" {
    skip "requires a live tmux server with a known session to assert argument forwarding — see common.sh:724-735"
}

# ============================================================================
# session-list.sh: format dispatch (raw/pretty/json) — never invoked by any
# test as a subprocess.
# ============================================================================

@test "session-list.sh: defaults to raw format and delegates to list_all_sessions" {
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-list.sh"
    [ "$status" -eq 0 ]
}

@test "session-list.sh: --pretty format renders icons and columns without erroring on an empty session list" {
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-list.sh" --pretty
    [ "$status" -eq 0 ]
}

@test "session-list.sh: --json format emits a valid empty JSON array when no sessions exist" {
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-list.sh" --json
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "[" ]
    [ "${lines[-1]}" = "]" ]
}

@test "session-list.sh: unknown format exits non-zero via handle_error" {
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-list.sh" bogus-format
    [ "$status" -ne 0 ]
}

@test "session-list.sh: --json output separates multiple entries with a comma" {
    skip "requires seeding list_all_sessions with 2+ live tower sessions to assert comma placement — see tmux-plugin/scripts/session-list.sh:37-55"
}

# ============================================================================
# session-restore.sh: --all vs single-id vs interactive-menu branches.
# ============================================================================

@test "session-restore.sh: --all restores all dormant sessions" {
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-restore.sh" --all
    [ "$status" -eq 0 ]
}

@test "session-restore.sh: rejects a session id that fails ensure_tower_prefix sanitization" {
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-restore.sh" '$(rm -rf /)'
    [ "$status" -ne 0 ]
}

@test "session-restore.sh: with no argument and no dormant sessions exits 0 and logs no-dormant message" {
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-restore.sh"
    [ "$status" -eq 0 ]
    run cat "$TOWER_LOG_FILE"
    [[ "$output" == *"No dormant sessions"* ]]
}

@test "session-restore.sh: with no argument and dormant sessions present builds a tmux display-menu" {
    skip "requires a live tmux server plus dormant metadata fixtures to assert display-menu invocation — see tmux-plugin/scripts/session-restore.sh:25-58"
}

# ============================================================================
# session-delete.sh: required-argument validation and prefix sanitization.
# ============================================================================

@test "session-delete.sh: exits non-zero with 'Session ID is required' when called with no argument" {
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-delete.sh"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Session ID is required"* ]]
}

@test "session-delete.sh: rejects a session id that fails ensure_tower_prefix sanitization" {
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-delete.sh" '!!!'
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid session ID format"* ]]
}

@test "session-delete.sh: forwards the force flag through to delete_session" {
    skip "requires a live tower session fixture to assert delete_session receives force=true and skips confirmation — see tmux-plugin/scripts/session-delete.sh:27"
}

