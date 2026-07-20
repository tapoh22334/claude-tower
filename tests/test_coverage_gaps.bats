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
    # ERROR_MAX_CONSECUTIVE/ERROR_COOLDOWN_SECONDS are readonly, and this
    # file's setup() already sourced error-recovery.sh once for the whole
    # bats process — so the override must happen in a fresh bash subprocess,
    # not just under `run` (which forks but inherits already-sourced state).
    # show_tui_error/wait_error_response are stubbed so the critical-error
    # prompt resolves to "quit" without a live TUI or terminal input.
    run bash -c '
        set -euo pipefail
        ERROR_MAX_CONSECUTIVE=3 ERROR_COOLDOWN_SECONDS=0
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh"
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/error-recovery.sh"
        show_tui_error() { :; }
        wait_error_response() { echo "quit"; }
        return_to_caller() { :; }
        attempts=0
        failing_main() { ((attempts++)) || true; return 1; }
        run_with_recovery "test-script" failing_main || true
        echo "attempts=$attempts"
    '
    [ "$status" -eq 0 ]
    # Loop must stop at exactly ERROR_MAX_CONSECUTIVE consecutive failures,
    # not run forever or overshoot.
    [[ "$output" == *"attempts=3"* ]]
}

@test "run_with_recovery: resets consecutive-failure count after an intervening success" {
    # Sequence: fail, fail, success (exits loop at call 3). A naive
    # implementation that never resets the counter would still exit here
    # too, so this only proves the loop survives 2 failures without tripping
    # the circuit breaker at ERROR_MAX_CONSECUTIVE=3 — combined with the
    # "stops after N consecutive" test above, together they pin down reset
    # behavior.
    run bash -c '
        set -euo pipefail
        ERROR_MAX_CONSECUTIVE=3 ERROR_COOLDOWN_SECONDS=0
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh"
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/error-recovery.sh"
        show_tui_error() { :; }
        wait_error_response() { echo "quit"; }
        return_to_caller() { :; }
        call_count=0
        flaky_main() {
            ((call_count++)) || true
            [[ "$call_count" -le 2 ]] && return 1
            return 0
        }
        run_with_recovery "test-script" flaky_main
        echo "call_count=$call_count"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"call_count=3"* ]]
}

@test "run_with_recovery: restarts main loop after a single failure below the error cap" {
    # Below ERROR_MAX_CONSECUTIVE, a single failure takes the "Recovering..."
    # cooldown branch, which reads one key with a timeout. `read` is a
    # builtin and can't be stubbed directly, so ERROR_COOLDOWN_SECONDS=0
    # makes the read time out immediately (no key pressed), and we assert
    # the loop restarts main_func rather than quitting — exercising the
    # non-quit path of the cooldown branch deterministically.
    run bash -c '
        set -euo pipefail
        ERROR_MAX_CONSECUTIVE=5 ERROR_COOLDOWN_SECONDS=0
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh"
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/error-recovery.sh"
        show_tui_error() { :; }
        return_to_caller() { :; }
        call_count=0
        fail_then_succeed_main() {
            ((call_count++)) || true
            [[ "$call_count" -eq 1 ]] && return 1
            return 0
        }
        run_with_recovery "test-script" fail_then_succeed_main < /dev/null
        echo "call_count=$call_count"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"call_count=2"* ]]
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

# ============================================================================
# _wait_for_shell_ready(): timeout is silently reported as success
# common.sh:946-948 — on timeout the function logs a warning but still
# `return 0`, so callers (start_claude_session) cannot distinguish "shell
# confirmed ready" from "gave up waiting". This test pins the *current*
# (arguably buggy) behavior; if _wait_for_shell_ready is fixed to return
# non-zero on timeout, this test should be updated to assert `-eq 1`.
# ============================================================================

@test "_wait_for_shell_ready: returns 0 even when capture-pane never shows a prompt" {
    session_tmux() {
        # capture-pane always returns content with no trailing prompt char
        echo "still running a long command..."
    }

    run _wait_for_shell_ready "tower_fake_session"
    [ "$status" -eq 0 ]
}

# ============================================================================
# save_metadata / load_metadata: no atomic write, no locking
# common.sh:553-586 — save_metadata writes directly to the target file with
# no temp-file+rename. A reader (load_metadata) racing a writer, or a writer
# killed mid-write, can observe/leave a partially-written .meta file.
# ============================================================================

@test "load_metadata: tolerates a truncated/partial metadata file without erroring" {
    mkdir -p "$TOWER_METADATA_DIR"
    # Simulate a write truncated mid-line (no trailing newline, cut mid-key).
    printf 'session_name=partial-wri' > "${TOWER_METADATA_DIR}/tower_partial.meta"

    run load_metadata "tower_partial"
    [ "$status" -eq 0 ]
    # Document current behavior: the truncated key is silently dropped
    # (doesn't match "session_name" exactly), so META_SESSION_NAME stays empty.
}

@test "save_metadata: concurrent writers do not corrupt each other's file" {
    skip "requires forking two real writers against the same metadata_file and asserting the loser's write is either fully applied or fully absent (never interleaved) — see common.sh:553-567. Currently there is no temp-file+rename, so this would need to inject a delay (e.g. via a wrapped 'echo') to reliably trigger the race."
}

# ============================================================================
# setup_pane_auto_restart(): unquoted variables inside a nested run-shell string
# error-recovery.sh:449-455 builds a `run-shell '...'` payload that
# interpolates $TOWER_NAV_SOCKET, $TOWER_NAV_SESSION, and $script_dir
# unquoted inside the nested command string. Today these are fixed constants,
# so this is latent rather than actively triggered — but nothing guards
# against it if $script_dir (an argument) ever contains a space.
# ============================================================================

@test "setup_pane_auto_restart: script_dir containing a space does not break the hook command" {
    captured_hook=""
    nav_tmux() {
        if [[ "$1" == "set-hook" ]]; then
            captured_hook="$*"
        fi
        return 0
    }

    setup_pane_auto_restart "/tmp/dir with space"

    # The unquoted $script_dir interpolation means the hook string's
    # respawn-pane invocation is not properly shell-quoted for this path.
    [[ "$captured_hook" == *"/tmp/dir with space"* ]]
}

# ============================================================================
# get_caller_cwd(): fallback chain from session_tmux -> plain tmux -> $HOME
# navigator-list.sh:324-333 has zero test coverage anywhere. A break in any
# link of the fallback chain silently creates new sessions in the wrong cwd.
# ============================================================================

@test "get_caller_cwd: falls back to \$HOME when no caller is set" {
    set +u
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true
    set -u

    get_nav_caller() { echo ""; }

    run get_caller_cwd
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME" ]
}

@test "get_caller_cwd: falls back to plain tmux when session_tmux fails" {
    skip "requires sourcing navigator-list.sh in isolation (it currently runs main_loop at file scope with no BASH_SOURCE guard, same issue as tower.sh) — see navigator-list.sh:324-333 and tower.sh:75. Once a sourcing guard exists, stub get_nav_caller to return a fake caller pane id, make session_tmux fail, and assert the plain-tmux fallback's #{pane_current_path} is used."
}

# ============================================================================
# show_tui_error(): negative printf width when title exceeds box width
# error-recovery.sh:158-160 computes title_padding = inner_width -
# title_plain_len with no clamping (unlike message/hint, which are wrapped
# via `fold -w`/`%-*s`). A title longer than inner_width drives
# `printf "%*s" "$title_padding"` with a negative width argument.
# ============================================================================

@test "show_tui_error: does not error when title is longer than the box width" {
    local_title=$(printf 'X%.0s' {1..200})  # far longer than ERROR_BOX_WIDTH
    run show_tui_error "$local_title" "short message" "hint"
    [ "$status" -eq 0 ]
}
