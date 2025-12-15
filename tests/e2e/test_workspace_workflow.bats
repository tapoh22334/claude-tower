#!/usr/bin/env bats
# E2E tests for workspace session workflow
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
# Full Workspace Workflow
# ============================================================================

@test "e2e: create workspace session from git repository" {
    skip_if_no_tmux

    local session_name="test-workspace"
    local session_id="tower_${session_name}"

    # Simulate workspace creation (without fzf interaction)
    local worktree_path="${CLAUDE_TOWER_WORKTREE_DIR}/${session_name}"
    local source_commit=$(git -C "$TEST_REPO" rev-parse HEAD)

    # Create worktree
    git -C "$TEST_REPO" worktree add -b "tower/${session_name}" "$worktree_path" "$source_commit"

    # Create tmux session
    tmux -L "$TMUX_SOCKET" new-session -d -s "$session_id" -c "$worktree_path"

    # Store session metadata
    tmux -L "$TMUX_SOCKET" set-option -t "$session_id" @tower_session_type "workspace"
    tmux -L "$TMUX_SOCKET" set-option -t "$session_id" @tower_repository "$TEST_REPO"
    tmux -L "$TMUX_SOCKET" set-option -t "$session_id" @tower_source "$source_commit"

    # Save metadata to file
    save_metadata "$session_id" "workspace" "$TEST_REPO" "$source_commit"

    # Verify everything is set up correctly
    [ -d "$worktree_path" ]
    [ -f "$worktree_path/README.md" ]

    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux
    run session_exists "$session_id"
    [ "$status" -eq 0 ]

    run has_metadata "$session_id"
    [ "$status" -eq 0 ]
}

@test "e2e: workspace session has isolated changes" {
    skip_if_no_tmux

    local session_name="isolated-workspace"
    local worktree_path="${CLAUDE_TOWER_WORKTREE_DIR}/${session_name}"
    local source_commit=$(git -C "$TEST_REPO" rev-parse HEAD)

    # Create worktree
    git -C "$TEST_REPO" worktree add -b "tower/${session_name}" "$worktree_path" "$source_commit"

    # Make changes in worktree
    echo "worktree change" >> "$worktree_path/README.md"

    # Verify main repo is unchanged
    main_content=$(cat "$TEST_REPO/README.md")
    worktree_content=$(cat "$worktree_path/README.md")

    [ "$main_content" = "initial" ]
    [[ "$worktree_content" == *"worktree change"* ]]

    # Cleanup
    git -C "$TEST_REPO" worktree remove --force "$worktree_path"
}

@test "e2e: cleanup removes orphaned workspace" {
    skip_if_no_tmux

    local session_name="orphan-test"
    local session_id="tower_${session_name}"
    local worktree_path="${CLAUDE_TOWER_WORKTREE_DIR}/${session_name}"
    local source_commit=$(git -C "$TEST_REPO" rev-parse HEAD)

    # Create worktree and metadata (but no tmux session)
    git -C "$TEST_REPO" worktree add -b "tower/${session_name}" "$worktree_path" "$source_commit"
    save_metadata "$session_id" "workspace" "$TEST_REPO" "$source_commit"

    # Override tmux to use our socket
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # Verify it's detected as orphan
    orphans=$(find_orphaned_worktrees)
    [[ "$orphans" == *"$session_id"* ]]

    # Clean up the orphan
    remove_orphaned_worktree "$session_id"

    # Verify cleanup
    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/${session_id}.meta" ]
    [ ! -d "$worktree_path" ]
}

# ============================================================================
# Simple Session Workflow
# ============================================================================

@test "e2e: create simple session" {
    skip_if_no_tmux

    local session_name="simple-test"
    local session_id="tower_${session_name}"

    # Create simple session (no worktree)
    tmux -L "$TMUX_SOCKET" new-session -d -s "$session_id" -c "/tmp"
    tmux -L "$TMUX_SOCKET" set-option -t "$session_id" @tower_session_type "simple"
    save_metadata "$session_id" "simple"

    # Verify
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux
    run session_exists "$session_id"
    [ "$status" -eq 0 ]

    load_metadata "$session_id"
    [ "$META_SESSION_TYPE" = "simple" ]
}

@test "e2e: simple session cleanup only removes metadata" {
    skip_if_no_tmux

    local session_name="simple-orphan"
    local session_id="tower_${session_name}"

    # Create metadata only (orphan)
    save_metadata "$session_id" "simple"

    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # Clean up
    remove_orphaned_worktree "$session_id"

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
