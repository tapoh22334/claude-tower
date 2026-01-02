#!/usr/bin/env bats
# Automated scenario tests
# Wraps scenario markdown files as bats tests

load '../test_helper'

SCENARIO_DIR="$BATS_TEST_DIRNAME"

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Scenario: Basic Session Creation (01_basic_session.md)
# ============================================================================

@test "scenario-01: create temporary test directory" {
    TEST_DIR=$(mktemp -d)
    [ -d "$TEST_DIR" ]
    rm -rf "$TEST_DIR"
}

@test "scenario-01: source common library succeeds" {
    run source_common
    [ "$status" -eq 0 ]
}

@test "scenario-01: create simple session manually" {
    local SESSION_NAME="scenario-test-simple-$$"
    local SESSION_ID="tower_${SESSION_NAME}"
    local TMUX_SOCKET="scenario-test-$$"

    # Create tmux session
    tmux -L "$TMUX_SOCKET" new-session -d -s "$SESSION_ID" -c /tmp

    # Set session type
    tmux -L "$TMUX_SOCKET" set-option -t "$SESSION_ID" @tower_session_type "simple"

    # Save metadata
    save_metadata "$SESSION_ID" "simple"

    # Verify session exists
    run tmux -L "$TMUX_SOCKET" has-session -t "$SESSION_ID"
    [ "$status" -eq 0 ]

    # Verify metadata was saved
    [ -f "${CLAUDE_TOWER_METADATA_DIR}/${SESSION_ID}.meta" ]
    grep -q "session_type=simple" "${CLAUDE_TOWER_METADATA_DIR}/${SESSION_ID}.meta"

    # Cleanup
    tmux -L "$TMUX_SOCKET" kill-session -t "$SESSION_ID"
    rm -f "${CLAUDE_TOWER_METADATA_DIR}/${SESSION_ID}.meta"
    tmux -L "$TMUX_SOCKET" kill-server 2>/dev/null || true
}

# ============================================================================
# Scenario: Workspace Session (02_workspace_session.md)
# ============================================================================

@test "scenario-02: create workspace with worktree" {
    local SESSION_NAME="scenario-workspace-$$"
    local SESSION_ID="tower_${SESSION_NAME}"
    local TMUX_SOCKET="scenario-ws-$$"
    local TEST_REPO

    # Create test repository
    TEST_REPO=$(mktemp -d)
    git -C "$TEST_REPO" init -q
    git -C "$TEST_REPO" config user.email "test@test.com"
    git -C "$TEST_REPO" config user.name "Test"
    echo "initial" > "$TEST_REPO/README.md"
    git -C "$TEST_REPO" add .
    git -C "$TEST_REPO" commit -q -m "Initial commit"

    local WORKTREE_PATH="${CLAUDE_TOWER_WORKTREE_DIR}/${SESSION_NAME}"
    local SOURCE_COMMIT
    SOURCE_COMMIT=$(git -C "$TEST_REPO" rev-parse HEAD)

    # Create worktree
    git -C "$TEST_REPO" worktree add -b "tower/${SESSION_NAME}" "$WORKTREE_PATH" "$SOURCE_COMMIT"

    # Verify worktree created
    [ -d "$WORKTREE_PATH" ]
    [ -f "$WORKTREE_PATH/README.md" ]

    # Create tmux session
    tmux -L "$TMUX_SOCKET" new-session -d -s "$SESSION_ID" -c "$WORKTREE_PATH"

    # Save metadata
    save_metadata "$SESSION_ID" "workspace" "$TEST_REPO" "$SOURCE_COMMIT"

    # Verify
    run tmux -L "$TMUX_SOCKET" has-session -t "$SESSION_ID"
    [ "$status" -eq 0 ]

    load_metadata "$SESSION_ID"
    [ "$META_SESSION_TYPE" = "workspace" ]
    [ "$META_REPOSITORY_PATH" = "$TEST_REPO" ]

    # Cleanup
    tmux -L "$TMUX_SOCKET" kill-session -t "$SESSION_ID"
    git -C "$TEST_REPO" worktree remove --force "$WORKTREE_PATH" 2>/dev/null || rm -rf "$WORKTREE_PATH"
    rm -f "${CLAUDE_TOWER_METADATA_DIR}/${SESSION_ID}.meta"
    rm -rf "$TEST_REPO"
    tmux -L "$TMUX_SOCKET" kill-server 2>/dev/null || true
}

@test "scenario-02: worktree changes are isolated" {
    local SESSION_NAME="scenario-isolated-$$"
    local TEST_REPO

    TEST_REPO=$(mktemp -d)
    git -C "$TEST_REPO" init -q
    git -C "$TEST_REPO" config user.email "test@test.com"
    git -C "$TEST_REPO" config user.name "Test"
    echo "original" > "$TEST_REPO/README.md"
    git -C "$TEST_REPO" add .
    git -C "$TEST_REPO" commit -q -m "Initial"

    local WORKTREE_PATH="${CLAUDE_TOWER_WORKTREE_DIR}/${SESSION_NAME}"
    git -C "$TEST_REPO" worktree add -b "tower/${SESSION_NAME}" "$WORKTREE_PATH"

    # Modify worktree
    echo "modified" >> "$WORKTREE_PATH/README.md"

    # Main repo unchanged
    local main_content
    main_content=$(cat "$TEST_REPO/README.md")
    [ "$main_content" = "original" ]

    # Worktree has changes
    local worktree_content
    worktree_content=$(cat "$WORKTREE_PATH/README.md")
    [[ "$worktree_content" == *"modified"* ]]

    # Cleanup
    git -C "$TEST_REPO" worktree remove --force "$WORKTREE_PATH" 2>/dev/null || rm -rf "$WORKTREE_PATH"
    rm -rf "$TEST_REPO"
}

# ============================================================================
# Scenario: Navigator Navigation
# ============================================================================

@test "scenario-nav: j/k navigation changes selection state" {
    local SESSIONS=("tower_nav_a" "tower_nav_b" "tower_nav_c")

    ensure_nav_state_dir

    # Start at first session
    set_nav_selected "tower_nav_a"

    # Simulate 'j' (down)
    local current_index=0
    local new_index=$((current_index + 1))
    set_nav_selected "${SESSIONS[$new_index]}"

    result=$(get_nav_selected)
    [ "$result" = "tower_nav_b" ]

    # Simulate 'k' (up)
    current_index=1
    new_index=$((current_index - 1))
    set_nav_selected "${SESSIONS[$new_index]}"

    result=$(get_nav_selected)
    [ "$result" = "tower_nav_a" ]

    cleanup_nav_state
}

@test "scenario-nav: g jumps to first, G jumps to last" {
    local SESSIONS=("tower_nav_a" "tower_nav_b" "tower_nav_c")

    ensure_nav_state_dir

    # Start in middle
    set_nav_selected "tower_nav_b"

    # Simulate 'g' (first)
    set_nav_selected "${SESSIONS[0]}"
    result=$(get_nav_selected)
    [ "$result" = "tower_nav_a" ]

    # Simulate 'G' (last)
    set_nav_selected "${SESSIONS[-1]}"
    result=$(get_nav_selected)
    [ "$result" = "tower_nav_c" ]

    cleanup_nav_state
}

@test "scenario-nav: i switches focus to view" {
    ensure_nav_state_dir

    set_nav_focus "list"
    [ "$(get_nav_focus)" = "list" ]

    # Simulate 'i' (view mode)
    set_nav_focus "view"
    [ "$(get_nav_focus)" = "view" ]

    cleanup_nav_state
}

# ============================================================================
# Scenario: Session Lifecycle
# ============================================================================

@test "scenario-lifecycle: dormant detection with metadata-only" {
    local SESSION_ID="tower_dormant_test_$$"

    # Create metadata without tmux session
    create_mock_metadata "$SESSION_ID" "workspace"

    # Override tmux to use a non-existent socket
    local TMUX_SOCKET="nonexistent-$$"
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # Should be detected as dormant
    run get_session_state "$SESSION_ID"
    [ "$status" -eq 0 ]
    [ "$output" = "dormant" ]
}

@test "scenario-lifecycle: cleanup removes metadata and worktree" {
    local SESSION_ID="tower_cleanup_test_$$"
    local TEST_REPO

    # Setup
    TEST_REPO=$(mktemp -d)
    git -C "$TEST_REPO" init -q
    git -C "$TEST_REPO" config user.email "test@test.com"
    git -C "$TEST_REPO" config user.name "Test"
    touch "$TEST_REPO/file.txt"
    git -C "$TEST_REPO" add .
    git -C "$TEST_REPO" commit -q -m "Init"

    local WORKTREE_PATH="${CLAUDE_TOWER_WORKTREE_DIR}/${SESSION_ID#tower_}"
    git -C "$TEST_REPO" worktree add -b "tower/${SESSION_ID#tower_}" "$WORKTREE_PATH"

    save_metadata "$SESSION_ID" "workspace" "$TEST_REPO" "abc123"

    # Verify setup
    [ -d "$WORKTREE_PATH" ]
    [ -f "${CLAUDE_TOWER_METADATA_DIR}/${SESSION_ID}.meta" ]

    # No tmux session - should be orphan
    local TMUX_SOCKET="cleanup-test-$$"
    tmux() { command tmux -L "$TMUX_SOCKET" "$@"; }
    export -f tmux

    # Cleanup
    remove_orphaned_worktree "$SESSION_ID"

    # Verify cleanup
    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/${SESSION_ID}.meta" ]
    [ ! -d "$WORKTREE_PATH" ]

    rm -rf "$TEST_REPO"
}

# ============================================================================
# Scenario: Error Handling
# ============================================================================

@test "scenario-error: invalid session name rejected" {
    run validate_session_name ""
    [ "$status" -eq 1 ]

    run validate_session_name "$(printf 'a%.0s' {1..100})"
    [ "$status" -eq 1 ]

    run validate_session_name "test/slash"
    [ "$status" -eq 1 ]
}

@test "scenario-error: command injection prevented" {
    run validate_tower_session_id "tower_; rm -rf /"
    [ "$status" -eq 1 ]

    run validate_tower_session_id 'tower_$(whoami)'
    [ "$status" -eq 1 ]

    run sanitize_name "../../../etc/passwd"
    [[ "$output" != *".."* ]]
    [[ "$output" != *"/"* ]]
}

@test "scenario-error: path traversal blocked" {
    run validate_path_within "/tmp/../etc/passwd" "/tmp"
    [ "$status" -eq 1 ]

    run validate_path_within "/tmp/safe/file" "/tmp"
    [ "$status" -eq 0 ]
}
