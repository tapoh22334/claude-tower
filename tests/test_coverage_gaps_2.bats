#!/usr/bin/env bats
# Additional coverage-gap skeletons, covering functions not addressed by
# test_coverage_gaps.bats, test_ensure_tower_prefix.bats, or
# test_error_recovery.bats. See conversation/report for full gap inventory.

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================================================
# _ensure_log_dir / _log_to_file: common.sh:23-33
# Zero existing coverage of the always-on logging path.
# ============================================================================

@test "_ensure_log_dir: creates TOWER_LOG_DIR if missing" {
    rm -rf "$TOWER_LOG_DIR"
    _ensure_log_dir
    [ -d "$TOWER_LOG_DIR" ]
}

@test "_log_to_file: appends a timestamped line with level and script name" {
    _log_to_file "INFO" "test message"
    [ -f "$TOWER_LOG_FILE" ]
    run cat "$TOWER_LOG_FILE"
    [[ "$output" == *"[INFO]"* ]]
    [[ "$output" == *"test message"* ]]
}

# ============================================================================
# _tower_error_trap: common.sh:36-60
# Global ERR trap under `set -euo pipefail` — never asserted to fire or log.
# ============================================================================

@test "_tower_error_trap: logs failing command to TOWER_LOG_FILE" {
    skip "requires triggering the ERR trap in a subshell with set -e and inspecting TOWER_LOG_FILE — see common.sh:36-60"
}

@test "_tower_error_trap: prints stack trace only when CLAUDE_TOWER_DEBUG=1" {
    skip "requires comparing trap output with CLAUDE_TOWER_DEBUG unset vs =1 — see common.sh:36-60"
}

# ============================================================================
# require_all_dependencies(): argument handling
# common.sh:481 ignores its positional arguments entirely and always checks
# a hardcoded (git tmux) — test_coverage_gaps.bats's existing tests for this
# function pass "bash"/"ls"/fake names but never actually exercise argument
# handling, since the function doesn't use $@. This test documents that gap.
# ============================================================================

@test "require_all_dependencies: BUG — ignores arguments, always checks hardcoded git+tmux" {
    # Calling with completely unrelated command names still only checks git/tmux.
    run require_all_dependencies "totally-unrelated-command-name"
    # If git and tmux are both present, this succeeds regardless of the arg,
    # proving the arguments are not consulted.
    [ "$status" -eq 0 ]
}

# ============================================================================
# is_nav_server_running / is_nav_session_exists / kill_nav_server
# common.sh:210-280 — zero coverage.
# ============================================================================

@test "is_nav_server_running: returns nonzero when nav socket does not exist" {
    export CLAUDE_TOWER_NAV_SOCKET="nonexistent-test-socket-$$"
    run is_nav_server_running
    [ "$status" -ne 0 ]
}

@test "is_nav_session_exists: returns nonzero when nav server is not running" {
    export CLAUDE_TOWER_NAV_SOCKET="nonexistent-test-socket-$$"
    run is_nav_session_exists
    [ "$status" -ne 0 ]
}

@test "kill_nav_server: succeeds (no-op) when nav server is not running" {
    export CLAUDE_TOWER_NAV_SOCKET="nonexistent-test-socket-$$"
    run kill_nav_server
    [ "$status" -eq 0 ]
}

# ============================================================================
# Spinner suite: common.sh:787-874
# Forks a background process and registers an EXIT trap. No test verifies
# the process is actually started/killed, or that _cleanup_spinner reaps it.
# ============================================================================

@test "start_spinner: sets SPINNER_PID to a running process" {
    skip "requires a tmux context for display-message and process-table inspection — see common.sh:787-808"
}

@test "stop_spinner: kills the spinner process and clears SPINNER_PID" {
    skip "requires starting a real spinner first — see common.sh:818-838"
}

@test "with_spinner: returns the wrapped command's exit code" {
    run with_spinner "msg" true
    [ "$status" -eq 0 ]
}

@test "with_spinner: propagates non-zero exit code from wrapped command" {
    run with_spinner "msg" false
    [ "$status" -ne 0 ]
}

@test "_cleanup_spinner: is a no-op when no spinner is running" {
    SPINNER_PID=""
    run _cleanup_spinner
    [ "$status" -eq 0 ]
}

# ============================================================================
# _wait_for_shell_ready(): common.sh:1184
# Polling loop with a silent-timeout fallback (returns 0 even on timeout).
# ============================================================================

@test "_wait_for_shell_ready: BUG-CHECK — silently returns 0 on timeout with no live tmux pane" {
    skip "requires a live tmux pane target to poll against, or a stub for capture-pane — see common.sh:1184-1210. Worth asserting whether timeout should be a failure instead of silent success."
}

# ============================================================================
# error-recovery.sh: TUI recovery flow — zero coverage
# show_tui_error / show_tui_status / wait_error_response / return_to_caller
# ============================================================================

@test "return_to_caller: falls back to any available tower session when caller session is gone" {
    skip "requires live tmux sessions to observe fallback selection — see error-recovery.sh:256-280"
}

@test "wait_error_response: returns the key pressed by the user" {
    skip "requires stubbing read -rsn1 -t — see error-recovery.sh:234-255"
}

# ============================================================================
# setup_pane_auto_restart(): error-recovery.sh:442
# ============================================================================

@test "setup_pane_auto_restart: sets remain-on-exit on the target pane" {
    skip "requires a live tmux pane to inspect pane options — see error-recovery.sh:442-467"
}

# ============================================================================
# tower.sh main(): the top-level CLI dispatcher has zero test references.
# Every subcommand routing decision is unverified.
# ============================================================================

@test "tower.sh: dispatches 'help' argument to show_help" {
    skip "tower.sh calls main \"\$@\" unconditionally at file scope with no BASH_SOURCE guard, so it cannot be sourced for unit testing without executing main as a side effect — see tmux-plugin/scripts/tower.sh. Consider adding a [[ \${BASH_SOURCE[0]} == \${0} ]] guard around the main invocation, or test via subprocess: run \"$PROJECT_ROOT/tmux-plugin/scripts/tower.sh\" help"
}

@test "tower.sh: unknown subcommand exits non-zero with usage message" {
    run "$PROJECT_ROOT/tmux-plugin/scripts/tower.sh" totally-unknown-subcommand
    [ "$status" -ne 0 ]
}

# ============================================================================
# navigator-list.sh core actions: delete_selected / restore_selected /
# create_session_inline — never invoked by any existing test, despite being
# the primary interactive verbs of the Navigator.
# ============================================================================

@test "navigator-list.sh: delete_selected removes the session under cursor" {
    skip "requires a live tmux navigator session + selection state file fixture — see tmux-plugin/scripts/navigator-list.sh:381-427"
}

@test "navigator-list.sh: restore_selected restores a dormant session under cursor" {
    skip "requires a live tmux navigator session + dormant metadata fixture — see tmux-plugin/scripts/navigator-list.sh:427-467"
}

