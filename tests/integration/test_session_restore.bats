#!/usr/bin/env bats
# Integration tests for session-restore.sh — focuses on dispatch behaviour
# (argument parsing, validation, empty-set handling) without driving the full
# claude-launch lifecycle, which requires a real interactive shell prompt
# detector. The actual restoration flow is exercised end-to-end by manual
# quickstart verification.

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
TEST_SOCKET="ct-restore-test-$$"

setup_file() {
    export TMUX_TMPDIR="/tmp/claude-tower-restore-test-$$"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"
}

teardown_file() {
    TMUX= tmux -L "$TEST_SOCKET" kill-server 2>/dev/null || true
    rm -rf "/tmp/claude-tower-restore-test-$$" 2>/dev/null || true
}

setup() {
    export CLAUDE_TOWER_SESSION_SOCKET="$TEST_SOCKET"
    export TMUX_TMPDIR="/tmp/claude-tower-restore-test-$$"
    export CLAUDE_TOWER_METADATA_DIR
    CLAUDE_TOWER_METADATA_DIR=$(mktemp -d)
    mkdir -p "$CLAUDE_TOWER_METADATA_DIR"
}

teardown() {
    # Kill any tower_* sessions left on the isolated socket so claude child
    # processes don't accumulate and stall bats teardown_file.
    TMUX= tmux -L "$TEST_SOCKET" list-sessions -F '#{session_name}' 2>/dev/null | \
        grep '^tower_' | \
        while read -r s; do
            TMUX= tmux -L "$TEST_SOCKET" kill-session -t "$s" 2>/dev/null || true
        done
    rm -rf "$CLAUDE_TOWER_METADATA_DIR" 2>/dev/null || true
}

skip_if_no_tmux() {
    if ! command -v tmux &>/dev/null; then
        skip "tmux not available"
    fi
}

make_dormant() {
    local name="$1"
    local dir="${2:-/tmp}"
    cat >"$CLAUDE_TOWER_METADATA_DIR/tower_${name}.meta" <<EOF
session_id=tower_${name}
session_name=${name}
directory_path=${dir}
created_at=$(date -Iseconds)
EOF
}

# ============================================================================
# --all path (the only path bin/tower uses post-003)
# ============================================================================

@test "session-restore.sh --all: exits successfully with zero dormant sessions" {
    skip_if_no_tmux
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-restore.sh" --all
    [ "$status" -eq 0 ]
}

@test "session-restore.sh: -a short flag accepted as --all" {
    skip_if_no_tmux
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-restore.sh" -a
    [ "$status" -eq 0 ]
}

@test "session-restore.sh --all: enumerates dormant sessions without hanging" {
    skip_if_no_tmux
    make_dormant "restore_report_a"
    make_dormant "restore_report_b"

    # Replace TOWER_PROGRAM with a no-op so we don't actually launch claude
    # and the restore terminates immediately. We still verify the enumeration
    # loop runs to completion.
    CLAUDE_TOWER_PROGRAM=/bin/true timeout 15 \
        "$PROJECT_ROOT/tmux-plugin/scripts/session-restore.sh" --all >/dev/null 2>&1
    local rc=$?
    [ $rc -ne 124 ] || { echo "timed out — restore loop did not terminate"; return 1; }
}

# ============================================================================
# Per-id path security: rejects malformed ids
# ============================================================================

@test "session-restore.sh <id>: rejects ids with shell metacharacters" {
    skip_if_no_tmux
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-restore.sh" 'tower_; rm -rf /'
    [ "$status" -ne 0 ]
}

@test "session-restore.sh <id>: rejects ids with command substitution" {
    skip_if_no_tmux
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-restore.sh" 'tower_$(whoami)'
    [ "$status" -ne 0 ]
}

@test "session-restore.sh <id>: rejects ids with path traversal" {
    skip_if_no_tmux
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-restore.sh" '../../etc/passwd'
    [ "$status" -ne 0 ]
}

# ============================================================================
# CLI surface: 'tower restore' always treats input as --all per 003
# ============================================================================

@test "tower restore: invocation does not error on empty dormant set" {
    skip_if_no_tmux
    run "$PROJECT_ROOT/tmux-plugin/bin/tower" restore
    [ "$status" -eq 0 ]
}

@test "tower restore: ignores positional argument (per FR-013, always --all)" {
    skip_if_no_tmux
    # Even with a bogus arg, exits 0 because no dormant sessions exist
    run "$PROJECT_ROOT/tmux-plugin/bin/tower" restore some-bogus-id-that-should-be-ignored
    [ "$status" -eq 0 ]
}
