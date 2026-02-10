#!/usr/bin/env bats
# E2E tests for session workflow (v2)
# Tests the full lifecycle: create -> use -> cleanup

load '../test_helper'

TMUX_SOCKET="claude-tower-e2e-$$"
TEST_REPO=""

setup_file() {
    # Use /tmp for tmux sockets to avoid WSL permission issues
    export TMUX_TMPDIR="/tmp/claude-tower-e2e-$$"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"

    # Create a test git repository
    TEST_REPO="${BATS_FILE_TMPDIR}/test-repo"
    mkdir -p "$TEST_REPO"
    git -C "$TEST_REPO" init -q
    git -C "$TEST_REPO" config user.email "test@test.com"
    git -C "$TEST_REPO" config user.name "Test"
    echo "initial" > "$TEST_REPO/README.md"
    git -C "$TEST_REPO" add .
    git -C "$TEST_REPO" commit -q -m "Initial commit"

    # Start tmux server
    tmux -L "$TMUX_SOCKET" new-session -d -s "e2e-base"
}

teardown_file() {
    tmux -L "$TMUX_SOCKET" kill-server 2>/dev/null || true
    rm -rf "${BATS_FILE_TMPDIR}"
    rm -rf "/tmp/claude-tower-e2e-$$" 2>/dev/null || true
}

setup() {
    # Set session socket BEFORE sourcing common.sh (TOWER_SESSION_SOCKET is readonly)
    export CLAUDE_TOWER_SESSION_SOCKET="$TMUX_SOCKET"
    # Use /tmp for tmux sockets to avoid WSL permission issues
    export TMUX_TMPDIR="/tmp/claude-tower-e2e-$$"
    source_common
    setup_test_env
    export TEST_REPO="${BATS_FILE_TMPDIR}/test-repo"
}

teardown() {
    # Clean up test sessions
    tmux -L "$TMUX_SOCKET" list-sessions -F '#{session_name}' 2>/dev/null | \
        grep "^tower_" | \
        while read -r session; do
            tmux -L "$TMUX_SOCKET" kill-session -t "$session" 2>/dev/null || true
        done
    teardown_test_env
}

# ============================================================================
# Directory-Based Session Workflow (v2)
# ============================================================================

@test "e2e: create session for a directory" {
    skip_if_no_tmux

    local session_name="test-dir-session"
    local session_id="tower_${session_name}"

    # Create tmux session pointing to test repo directory
    session_tmux new-session -d -s "$session_id" -c "$TEST_REPO"

    # Save v2 metadata
    save_metadata "$session_id" "$TEST_REPO"

    # Verify session exists
    run session_exists "$session_id"
    [ "$status" -eq 0 ]

    # Verify metadata
    run has_metadata "$session_id"
    [ "$status" -eq 0 ]

    load_metadata "$session_id"
    [ "$META_DIRECTORY_PATH" = "$TEST_REPO" ]
}

@test "e2e: session directory is independent from session" {
    skip_if_no_tmux

    local session_name="isolated-session"
    local session_id="tower_${session_name}"

    # Create session for test repo
    session_tmux new-session -d -s "$session_id" -c "$TEST_REPO"
    save_metadata "$session_id" "$TEST_REPO"

    # Make changes in the directory
    echo "session change" >> "$TEST_REPO/README.md"

    # Verify the file was changed
    worktree_content=$(cat "$TEST_REPO/README.md")
    [[ "$worktree_content" == *"session change"* ]]

    # Cleanup - restore file
    echo "initial" > "$TEST_REPO/README.md"

    session_tmux kill-session -t "$session_id"
}

@test "e2e: cleanup removes orphaned metadata" {
    skip_if_no_tmux

    local session_name="orphan-test"
    local session_id="tower_${session_name}"

    # Create metadata only (no tmux session = orphaned)
    save_metadata "$session_id" "$TEST_REPO"

    # Verify it's detected as orphaned metadata
    orphans=$(find_orphaned_metadata)
    [[ "$orphans" == *"$session_id"* ]]

    # Clean up the orphan
    remove_orphaned_metadata "$session_id"

    # Verify metadata removed
    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/${session_id}.meta" ]

    # Verify directory still exists (v2: never deleted)
    [ -d "$TEST_REPO" ]
}

# ============================================================================
# Simple Session Workflow
# ============================================================================

@test "e2e: create simple session" {
    skip_if_no_tmux

    local session_name="simple-test"
    local session_id="tower_${session_name}"

    # Create simple session
    session_tmux new-session -d -s "$session_id" -c "/tmp"
    save_metadata "$session_id" "/tmp"

    # Verify
    run session_exists "$session_id"
    [ "$status" -eq 0 ]

    load_metadata "$session_id"
    [ "$META_DIRECTORY_PATH" = "/tmp" ]
}

@test "e2e: simple session cleanup only removes metadata" {
    skip_if_no_tmux

    local session_name="simple-orphan"
    local session_id="tower_${session_name}"

    # Create metadata only (orphan)
    save_metadata "$session_id" "/tmp"

    # Clean up
    remove_orphaned_metadata "$session_id"

    # Verify metadata removed
    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/${session_id}.meta" ]
}

# ============================================================================
# Helper Functions
# ============================================================================

skip_if_no_tmux() {
    if ! command -v tmux &>/dev/null; then
        skip "tmux not available"
    fi
}
