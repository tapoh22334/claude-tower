#!/usr/bin/env bats
# Unit tests for tmux-plugin/lib/error-recovery.sh — covers the pure-function
# parts of the library (command-runner wrappers and error classification).
# Display functions (show_tui_error etc.) are smoke-tested separately to
# confirm they do not crash.

load 'test_helper'

setup() {
    source_common
    # error-recovery.sh must be sourced after common.sh per its header.
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/tmux-plugin/lib/error-recovery.sh"
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================================================
# try_command — never exits, returns underlying exit code
# ============================================================================

@test "try_command: returns 0 on successful command" {
    run try_command "test" true
    [ "$status" -eq 0 ]
}

@test "try_command: returns underlying exit code on failure" {
    run try_command "test" bash -c "exit 7"
    [ "$status" -eq 7 ]
}

@test "try_command: captures stdout from the command" {
    run try_command "test" echo "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "try_command: tolerates command not found" {
    run try_command "test" some-command-that-does-not-exist-$$
    [ "$status" -ne 0 ]
    # Must not propagate as a hard error — we got a status back.
}

# ============================================================================
# try_with_retry — retries up to max_retries times, then gives up
# ============================================================================

@test "try_with_retry: returns 0 immediately when command succeeds first try" {
    run try_with_retry 3 0 true
    [ "$status" -eq 0 ]
}

@test "try_with_retry: returns non-zero after max_retries failures" {
    # 2 retries, no delay, always-fail command
    run try_with_retry 2 0 false
    [ "$status" -ne 0 ]
}

@test "try_with_retry: succeeds when command becomes available mid-retry" {
    # Use a counter file as a poor man's "succeed on second try"
    local marker
    marker=$(mktemp)
    rm -f "$marker"

    # First call creates the marker and fails; second call finds it and succeeds.
    run try_with_retry 3 0 bash -c "
        if [ -f '$marker' ]; then
            exit 0
        else
            touch '$marker'
            exit 1
        fi
    "
    [ "$status" -eq 0 ]
    rm -f "$marker"
}

@test "try_with_retry: respects max_retries=1 (single attempt)" {
    # With max=1 there should be no retry — single attempt only
    local counter
    counter=$(mktemp)
    echo 0 >"$counter"

    try_with_retry 1 0 bash -c "
        n=\$(cat '$counter')
        echo \$((n + 1)) > '$counter'
        exit 1
    " || true

    local n
    n=$(cat "$counter")
    [ "$n" = "1" ]
    rm -f "$counter"
}

# ============================================================================
# classify_error — maps (exit_code, message) → category
# ============================================================================

@test "classify_error: recognises session-missing errors" {
    run classify_error 1 "no session found: foo"
    [ "$output" = "session_missing" ]

    run classify_error 1 "tmux: session not found"
    [ "$output" = "session_missing" ]
}

@test "classify_error: recognises transient/network errors" {
    run classify_error 1 "no server running on /tmp/socket"
    [ "$output" = "transient" ]

    run classify_error 1 "connection refused"
    [ "$output" = "transient" ]
}

@test "classify_error: recognises config errors" {
    run classify_error 2 "config file missing at /etc/foo"
    [ "$output" = "config" ]
}

@test "classify_error: defaults exit_code=1 to transient" {
    run classify_error 1 "some generic failure"
    [ "$output" = "transient" ]
}

@test "classify_error: defaults non-1 exit codes to fatal" {
    # Message must not match any of the patterns ("not found", "missing",
    # "connection refused", "session not found", "no session", etc.)
    run classify_error 127 "something went wrong in an unrelated way"
    [ "$output" = "fatal" ]
}

# ============================================================================
# get_error_action — maps category → recovery action
# ============================================================================

@test "get_error_action: transient → retry" {
    run get_error_action "transient"
    [ "$output" = "retry" ]
}

@test "get_error_action: session_missing → refresh" {
    run get_error_action "session_missing"
    [ "$output" = "refresh" ]
}

@test "get_error_action: config → warn" {
    run get_error_action "config"
    [ "$output" = "warn" ]
}

@test "get_error_action: fatal → exit" {
    run get_error_action "fatal"
    [ "$output" = "exit" ]
}

@test "get_error_action: unknown category falls back to retry" {
    run get_error_action "made-up-category"
    [ "$output" = "retry" ]
}

# ============================================================================
# Display smoke tests — these MUST NOT crash even in non-tty environments
# ============================================================================

@test "show_tui_error: does not crash when invoked" {
    # Capture both stdout and stderr; we don't validate visuals, only that
    # the function returns cleanly.
    run show_tui_error "Test Title" "Test message body" "Press q"
    [ "$status" -eq 0 ]
}

@test "show_tui_status: does not crash when invoked" {
    # Second arg is sleep duration in seconds — pass 0 so the test does not stall.
    run show_tui_status "Status message" 0
    [ "$status" -eq 0 ]
}
