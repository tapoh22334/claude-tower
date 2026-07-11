#!/usr/bin/env bats
# Skeletons for high-priority coverage gaps identified in test-coverage analysis.
# Each @test documents the gap; fill in the body (or fix the source) as needed.
# See conversation/report for full gap inventory — this file only covers the
# highest-value, most concretely reproducible gaps.

load 'test_helper'

setup() {
    source_common
    setup_test_env
    set +euo pipefail
    source "$PROJECT_ROOT/tmux-plugin/lib/error-recovery.sh"
    set -euo pipefail
}

teardown() {
    teardown_test_env
}

# ============================================================================
# validate_path_within: sibling-directory prefix bug
# common.sh:352 does `[[ "$resolved_path" == "$resolved_base"* ]]`, a plain
# string-prefix check with no separator boundary. "/foo" is a string-prefix
# of "/foobar", so a sibling directory that merely starts with the same
# characters as base is incorrectly treated as "within" base.
# ============================================================================

@test "validate_path_within: rejects sibling dir sharing base as string prefix" {
    base="${TEST_DIR}/tmp/pathbase"
    mkdir -p "${base}bar"

    run validate_path_within "${base}bar/evil" "$base"
    [ "$status" -eq 1 ]
}

@test "validate_path_within: rejects base without trailing slash matching longer sibling" {
    base="${TEST_DIR}/tmp/pathbase"
    base="${base%/}"
    mkdir -p "${base}_sibling"

    run validate_path_within "${base}_sibling/file" "$base"
    [ "$status" -eq 1 ]
}

# ============================================================================
# confirm(): decline path and race between mktemp result file and read
# common.sh:511 confirm() — only the accept path (if any) is covered anywhere;
# decline path and the unwritten-result-file race are untested.
# ============================================================================

@test "confirm: returns zero when user accepts" {
    # Simulate the "Yes" menu item's run-shell callback firing synchronously:
    # extract the result-file path from the "echo yes > FILE" run-shell arg.
    tmux() {
        local result_file
        result_file=$(printf '%s\n' "$@" | grep -o '/tmp/[^'"'"']*' | head -1)
        [[ -n "$result_file" ]] && echo yes > "$result_file"
        return 0
    }
    run confirm "Delete session?"
    [ "$status" -eq 0 ]
}

@test "confirm: returns non-zero when user declines" {
    tmux() {
        local result_file
        result_file=$(printf '%s\n' "$@" | grep -o '/tmp/[^'"'"']*' | head -1)
        [[ -n "$result_file" ]] && echo no > "$result_file"
        return 0
    }
    run confirm "Delete session?"
    [ "$status" -ne 0 ]
}

@test "confirm: defaults to decline if result file never written (race)" {
    # tmux display-menu succeeds but its callback never fires (e.g. user
    # closes the menu via an unmapped key) — result_file stays empty.
    tmux() { return 0; }
    run confirm "Delete session?"
    [ "$status" -ne 0 ]
}

# ============================================================================
# require_all_dependencies(): multi-missing-dependency output format
# common.sh:481 — only single-command require_command is tested elsewhere.
# ============================================================================

@test "require_all_dependencies: succeeds when all dependencies present" {
    run require_all_dependencies "bash" "ls"
    [ "$status" -eq 0 ]
}

@test "require_all_dependencies: BUG — ignores its arguments, always checks hardcoded git+tmux" {
    # common.sh:480 never consults $@; it always checks a hardcoded (git tmux)
    # list. See test_coverage_gaps_2.bats for the same gap documented on the
    # single-arg case. This is dead code (no caller in tmux-plugin/scripts/
    # passes arguments, or calls it at all), so the test documents the bug
    # rather than asserting the originally-intended (but never implemented)
    # per-argument behavior.
    run require_all_dependencies "bash" "definitely-not-a-real-command-xyz" "also-not-real-abc"
    [ "$status" -eq 0 ]
}

# ============================================================================
# delete_session(): confirmation and existence branches
# common.sh:1298 — only declare -f string-grep coverage exists today.
# ============================================================================

@test "delete_session: fails gracefully when session does not exist" {
    run delete_session "tower_does-not-exist"
    [ "$status" -ne 0 ]
}

@test "delete_session: aborts when user declines confirmation" {
    # Isolate delete_session's own confirm-gate logic: stub get_display_state
    # so the session "exists", and stub tmux so confirm()'s menu callback
    # writes "no" to the result file. handle_info emits only via
    # `tmux display-message` (common.sh:413-417) — nothing to stdout — so the
    # stub echoes display-message payloads to make the message observable.
    get_display_state() { echo "dormant"; }
    tmux() {
        if [[ "${1:-}" == "display-message" ]]; then
            shift
            echo "$*"
            return 0
        fi
        local result_file
        result_file=$(printf '%s\n' "$@" | grep -o '/tmp/[^'"'"']*' | head -1)
        [[ -n "$result_file" ]] && echo no > "$result_file"
        return 0
    }

    run delete_session "tower_fake-session"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cancelled"* ]]
}

# ============================================================================
# restore_session(): dormant/active/missing-metadata branches
# common.sh:1244 — zero coverage today.
# ============================================================================

@test "restore_session: fails when session is not dormant (already active)" {
    skip "requires live tmux session fixture — see common.sh:1251-1258"
}

@test "restore_session: fails when metadata cannot be loaded" {
    run restore_session "tower_no-metadata-here"
    [ "$status" -ne 0 ]
}

# ============================================================================
# run_with_recovery(): consecutive-error counting and quit/retry handling
# error-recovery.sh:318 — stated as the core "Navigator never crashes"
# guarantee, but has zero test coverage.
# ============================================================================

@test "run_with_recovery: returns 0 immediately on clean exit" {
    clean_exit_main() { return 0; }
    run run_with_recovery "test-script" clean_exit_main
    [ "$status" -eq 0 ]
}

@test "run_with_recovery: stops retrying after ERROR_MAX_CONSECUTIVE consecutive failures" {
    skip "requires simulating repeated non-zero exits and asserting bounded retry count — see error-recovery.sh:318-390"
}

@test "run_with_recovery: honors user quit key during cooldown prompt" {
    skip "requires stubbing read -rsn1 -t input — see error-recovery.sh:318-390"
}

# ============================================================================
# classify_error(): pattern precedence with multiple simultaneous matches
# error-recovery.sh — case-statement ordering is unverified.
# ============================================================================

@test "classify_error: picks first matching category when message matches multiple patterns" {
    # Signature is classify_error(exit_code, error_msg) — error-recovery.sh:462-470.
    # "session not found: config error" matches both the session_missing and
    # config case arms; the case statement's arm order decides precedence.
    run classify_error 1 "session not found: config error"
    [ "$status" -eq 0 ]
    [ "$output" = "session_missing" ]
}

@test "classify_error: handles non-1 exit codes via fallback branch" {
    run classify_error 42 "some unrecognized failure"
    [ "$status" -eq 0 ]
    [ "$output" = "fatal" ]
}
