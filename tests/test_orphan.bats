#!/usr/bin/env bats
# Unit tests for orphan detection functions in common.sh

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================================================
# Mock tmux for testing
# ============================================================================

# Override get_active_sessions to return mock data
mock_active_sessions() {
    local sessions="$1"
    eval "get_active_sessions() { echo '$sessions'; }"
}

# ============================================================================
# find_orphaned_worktrees() tests
# ============================================================================

@test "find_orphaned_worktrees: returns empty when no metadata exists" {
    mock_active_sessions ""

    result=$(find_orphaned_worktrees)
    [ -z "$result" ]
}

@test "find_orphaned_worktrees: returns empty when all sessions are active" {
    create_mock_metadata "tower_active1"
    create_mock_metadata "tower_active2"

    mock_active_sessions "tower_active1
tower_active2"

    result=$(find_orphaned_worktrees)
    [ -z "$result" ]
}

@test "find_orphaned_worktrees: finds orphaned session" {
    create_mock_metadata "tower_orphan"

    mock_active_sessions ""

    result=$(find_orphaned_worktrees)
    [ "$result" = "tower_orphan" ]
}

@test "find_orphaned_worktrees: finds multiple orphaned sessions" {
    create_mock_metadata "tower_orphan1"
    create_mock_metadata "tower_orphan2"
    create_mock_metadata "tower_active"

    mock_active_sessions "tower_active"

    result=$(find_orphaned_worktrees | sort)
    expected=$(printf "tower_orphan1\ntower_orphan2")

    [ "$result" = "$expected" ]
}

@test "find_orphaned_worktrees: distinguishes active from orphaned" {
    create_mock_metadata "tower_active"
    create_mock_metadata "tower_orphan"

    mock_active_sessions "tower_active"

    result=$(find_orphaned_worktrees)
    [ "$result" = "tower_orphan" ]
}

# ============================================================================
# remove_orphaned_worktree() tests
# ============================================================================

@test "remove_orphaned_worktree: returns 1 when metadata does not exist" {
    run remove_orphaned_worktree "tower_nonexistent"
    [ "$status" -eq 1 ]
}

@test "remove_orphaned_worktree: deletes metadata for simple session" {
    create_mock_metadata "tower_simple" "simple"

    remove_orphaned_worktree "tower_simple"

    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/tower_simple.meta" ]
}

@test "remove_orphaned_worktree: deletes metadata for workspace session without worktree" {
    create_mock_metadata "tower_workspace" "workspace" "/mock/repo"

    # Don't create actual worktree directory
    remove_orphaned_worktree "tower_workspace"

    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/tower_workspace.meta" ]
}

@test "remove_orphaned_worktree: handles workspace with missing repository" {
    # Create metadata pointing to non-existent repo
    create_mock_metadata "tower_test" "workspace" "/nonexistent/repo"

    # Create worktree directory
    mkdir -p "${CLAUDE_TOWER_WORKTREE_DIR}/test"

    remove_orphaned_worktree "tower_test"

    # Metadata should be deleted
    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/tower_test.meta" ]
    # Worktree should be removed (manually since repo doesn't exist)
    [ ! -d "${CLAUDE_TOWER_WORKTREE_DIR}/test" ]
}

@test "remove_orphaned_worktree: returns 0 on success" {
    create_mock_metadata "tower_test" "simple"

    run remove_orphaned_worktree "tower_test"
    [ "$status" -eq 0 ]
}

# ============================================================================
# cleanup_orphaned_worktree() backwards compatibility tests
# ============================================================================

@test "cleanup_orphaned_worktree: is alias for remove_orphaned_worktree" {
    create_mock_metadata "tower_alias-test" "simple"

    cleanup_orphaned_worktree "tower_alias-test"

    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/tower_alias-test.meta" ]
}

# ============================================================================
# Path validation in orphan cleanup
# ============================================================================

@test "remove_orphaned_worktree: validates worktree path before removal" {
    # Create metadata with a worktree path that would be outside the allowed directory
    # This tests the validate_path_within check
    cat > "${CLAUDE_TOWER_METADATA_DIR}/tower_malicious.meta" << EOF
session_id=tower_malicious
session_type=workspace
repository_path=/mock/repo
source_commit=abc123
worktree_path=/etc/passwd
EOF

    # Should not attempt to remove /etc/passwd
    remove_orphaned_worktree "tower_malicious"

    # /etc/passwd should still exist (we didn't delete it)
    [ -f "/etc/passwd" ]
}
