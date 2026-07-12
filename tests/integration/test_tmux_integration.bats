#!/usr/bin/env bats
# Integration tests for tmux interaction
# These tests require a real tmux server to be running

load '../test_helper'

# Start a dedicated tmux server for tests
TMUX_SOCKET="claude-tower-test-$$"

setup_file() {
    # Use /tmp for tmux sockets to avoid WSL permission issues
    export TMUX_TMPDIR="/tmp/claude-tower-test-$$"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"
    # Start a new tmux server for testing
    tmux -L "$TMUX_SOCKET" new-session -d -s "test-base" 2>/dev/null || true
}

teardown_file() {
    # Kill the test tmux server
    tmux -L "$TMUX_SOCKET" kill-server 2>/dev/null || true
    # Clean up tmux socket directory
    rm -rf "/tmp/claude-tower-test-$$" 2>/dev/null || true
}

setup() {
    # session_exists() routes through session_tmux(), which hardcodes
    # `tmux -L "$TOWER_SESSION_SOCKET"`. tmux only honors the LAST -L flag on
    # its command line, so overriding the `tmux` shell function is silently
    # defeated by session_tmux's own explicit -L. Point TOWER_SESSION_SOCKET
    # at our test socket instead (must be set before source_common, since
    # it's readonly once common.sh is sourced).
    export CLAUDE_TOWER_SESSION_SOCKET="$TMUX_SOCKET"
    source_common
    setup_test_env
    # Use /tmp for tmux sockets to avoid WSL permission issues
    export TMUX_TMPDIR="/tmp/claude-tower-test-$$"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"
}

teardown() {
    # Clean up any sessions created during tests
    tmux -L "$TMUX_SOCKET" kill-session -t "tower_test" 2>/dev/null || true
    teardown_test_env
}

# ============================================================================
# session_exists() tests with real tmux
# ============================================================================

@test "integration: session_exists returns true for existing session" {
    # Create a test session
    tmux -L "$TMUX_SOCKET" new-session -d -s "tower_exists_test"

    # Override tmux to use our socket
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    run session_exists "tower_exists_test"
    [ "$status" -eq 0 ]

    tmux -L "$TMUX_SOCKET" kill-session -t "tower_exists_test"
}

@test "integration: session_exists returns false for non-existing session" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    run session_exists "tower_nonexistent_xyz"
    [ "$status" -eq 1 ]
}

# ============================================================================
# safe_tmux() tests with real tmux
# ============================================================================

@test "integration: safe_tmux creates session" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    run safe_tmux new-session -d -s "tower_safe_test"
    [ "$status" -eq 0 ]

    # Verify session exists
    run tmux -L "$TMUX_SOCKET" has-session -t "tower_safe_test"
    [ "$status" -eq 0 ]

    tmux -L "$TMUX_SOCKET" kill-session -t "tower_safe_test"
}

@test "integration: safe_tmux fails gracefully for invalid command" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    run safe_tmux invalid-command-xyz
    [ "$status" -eq 1 ]
}

# ============================================================================
# Registry data model tests (v2026-07-11 redesign)
# ============================================================================
# The old per-session tmux @tower_* options (session_type/repository/source)
# were part of the pre-redesign worktree-tracking data model and were
# removed along with session_type/repository_path/source_commit/worktree_path
# /branch_name (see docs/superpowers/specs/2026-07-11-tower-session-registry-design.md
# section 2 and 7). The registry is now a minimal .meta file
# (session_name + created_at); unknown legacy keys are ignored on read.

@test "integration: metadata file only carries session_name and created_at" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    create_mock_metadata "tower_meta_shape_test" "workspace"

    # load_metadata sets META_SESSION_NAME/META_CREATED_AT as globals in the
    # current shell; `run` would execute it in a subshell and lose them, so
    # call it directly.
    load_metadata "tower_meta_shape_test"
    [ "$META_SESSION_NAME" = "workspace" ]
}

@test "integration: legacy metadata keys (session_type/repository_path) are ignored, not fatal" {
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    ensure_metadata_dir
    {
        echo "session_type=workspace"
        echo "repository_path=/old/repo"
        echo "session_name=kept"
        echo "created_at=2026-01-01T00:00:00"
    } > "${TOWER_METADATA_DIR}/tower_legacy_meta_test.meta"

    load_metadata "tower_legacy_meta_test"
    [ "$META_SESSION_NAME" = "kept" ]
}
