#!/usr/bin/env bats
# Unit tests for tmux-plugin/lib/error-recovery.sh
# This file currently has zero test coverage.

load 'test_helper'

setup() {
    export CLAUDE_TOWER_NAV_SOCKET="nonexistent-test-socket-$$"
    source_common
    set +euo pipefail
    source "$PROJECT_ROOT/tmux-plugin/lib/error-recovery.sh"
    set -euo pipefail
}

# ============================================================================
# classify_error() tests
# ============================================================================

@test "classify_error: recognizes session-missing message" {
    result=$(classify_error 1 "session not found")
    [ "$result" = "session_missing" ]
}

@test "classify_error: recognizes transient connection errors" {
    result=$(classify_error 1 "connection refused")
    [ "$result" = "transient" ]
}

@test "classify_error: recognizes config errors" {
    result=$(classify_error 1 "config file missing")
    [ "$result" = "config" ]
}

@test "classify_error: falls back based on exit code for unrecognized message" {
    result=$(classify_error 1 "some unrelated message")
    [ -n "$result" ]
}

@test "classify_error: handles empty error message" {
    run classify_error 1 ""
    [ "$status" -eq 0 ]
}

# ============================================================================
# get_error_action() tests
# ============================================================================

@test "get_error_action: transient maps to retry" {
    result=$(get_error_action "transient")
    [ "$result" = "retry" ]
}

@test "get_error_action: session_missing maps to refresh" {
    result=$(get_error_action "session_missing")
    [ "$result" = "refresh" ]
}

@test "get_error_action: config maps to warn" {
    result=$(get_error_action "config")
    [ "$result" = "warn" ]
}

@test "get_error_action: fatal maps to exit" {
    result=$(get_error_action "fatal")
    [ "$result" = "exit" ]
}

@test "get_error_action: unknown type defaults to retry" {
    result=$(get_error_action "totally_unknown_type")
    [ "$result" = "retry" ]
}

# ============================================================================
# try_command() tests
# ============================================================================

@test "try_command: returns 0 and output on success" {
    run try_command "prefix" echo "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "try_command: returns nonzero exit code from failing command" {
    run try_command "prefix" false
    [ "$status" -ne 0 ]
}

@test "try_command: preserves errexit state after call" {
    set -e
    try_command "prefix" true
    # if errexit leaked off, this comment-only assertion still needs a real check:
    [[ $- == *e* ]]
}

# ============================================================================
# try_with_retry() tests
# ============================================================================

@test "try_with_retry: succeeds immediately without retrying" {
    run try_with_retry 3 0 true
    [ "$status" -eq 0 ]
}

@test "try_with_retry: retries up to max_retries then fails" {
    run try_with_retry 2 0 false
    [ "$status" -ne 0 ]
}

@test "try_with_retry: succeeds on a later attempt (flaky command simulation)" {
    local counter_file
    counter_file="$(mktemp)"
    echo 0 > "$counter_file"

    flaky_cmd() {
        local n
        n=$(cat "$counter_file")
        n=$((n + 1))
        echo "$n" > "$counter_file"
        [[ "$n" -ge 2 ]]
    }

    run try_with_retry 3 0 flaky_cmd
    [ "$status" -eq 0 ]
    rm -f "$counter_file"
}

# ============================================================================
# safe_nav_tmux() / safe_signal_view() tests
# ============================================================================

@test "safe_nav_tmux: returns nonzero when nav server is not running" {
    run safe_nav_tmux list-sessions
    [ "$status" -ne 0 ]
}

@test "safe_signal_view: never fails even when nav server is not running" {
    run safe_signal_view
    [ "$status" -eq 0 ]
}
