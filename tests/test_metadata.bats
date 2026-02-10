#!/usr/bin/env bats
# Unit tests for metadata functions in common.sh

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================================================
# save_metadata() tests (v2 format)
# ============================================================================

@test "save_metadata: creates metadata file" {
    save_metadata "tower_test-session" "/path/to/workdir"

    [ -f "${CLAUDE_TOWER_METADATA_DIR}/tower_test-session.meta" ]
}

@test "save_metadata: stores session_id" {
    save_metadata "tower_myproject" "/path/to/workdir"

    grep -q "session_id=tower_myproject" "${CLAUDE_TOWER_METADATA_DIR}/tower_myproject.meta"
}

@test "save_metadata: stores session_name (derived from session_id)" {
    save_metadata "tower_myproject" "/path/to/workdir"

    grep -q "session_name=myproject" "${CLAUDE_TOWER_METADATA_DIR}/tower_myproject.meta"
}

@test "save_metadata: stores directory_path" {
    save_metadata "tower_myproject" "/custom/directory/path"

    grep -q "directory_path=/custom/directory/path" "${CLAUDE_TOWER_METADATA_DIR}/tower_myproject.meta"
}

@test "save_metadata: stores created_at timestamp" {
    save_metadata "tower_myproject" "/path/to/workdir"

    grep -q "created_at=" "${CLAUDE_TOWER_METADATA_DIR}/tower_myproject.meta"
}

# ============================================================================
# load_metadata() tests (v2 format)
# ============================================================================

@test "load_metadata: returns 0 when file exists" {
    # Create v2 format metadata
    save_metadata "tower_test" "/path/to/workdir"

    run load_metadata "tower_test"
    [ "$status" -eq 0 ]
}

@test "load_metadata: returns 1 when file does not exist" {
    run load_metadata "tower_nonexistent"
    [ "$status" -eq 1 ]
}

@test "load_metadata: sets META_SESSION_NAME" {
    save_metadata "tower_my-project" "/path/to/workdir"

    load_metadata "tower_my-project"
    [ "$META_SESSION_NAME" = "my-project" ]
}

@test "load_metadata: sets META_DIRECTORY_PATH" {
    save_metadata "tower_test" "/custom/directory/path"

    load_metadata "tower_test"
    [ "$META_DIRECTORY_PATH" = "/custom/directory/path" ]
}

@test "load_metadata: sets META_CREATED_AT" {
    save_metadata "tower_test" "/path/to/workdir"

    load_metadata "tower_test"
    [ -n "$META_CREATED_AT" ]
}

# ============================================================================
# delete_metadata() tests
# ============================================================================

@test "delete_metadata: removes existing metadata file" {
    create_mock_metadata "tower_to-delete"
    [ -f "${CLAUDE_TOWER_METADATA_DIR}/tower_to-delete.meta" ]

    delete_metadata "tower_to-delete"

    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/tower_to-delete.meta" ]
}

@test "delete_metadata: succeeds silently when file does not exist" {
    run delete_metadata "tower_nonexistent"
    [ "$status" -eq 0 ]
}

# ============================================================================
# has_metadata() tests
# ============================================================================

@test "has_metadata: returns 0 when metadata exists" {
    create_mock_metadata "tower_exists"

    run has_metadata "tower_exists"
    [ "$status" -eq 0 ]
}

@test "has_metadata: returns 1 when metadata does not exist" {
    run has_metadata "tower_nonexistent"
    [ "$status" -eq 1 ]
}

# ============================================================================
# list_metadata() tests
# ============================================================================

@test "list_metadata: lists all metadata files" {
    create_mock_metadata "tower_session1"
    create_mock_metadata "tower_session2"
    create_mock_metadata "tower_session3"

    result=$(list_metadata | sort)
    expected=$(printf "tower_session1\ntower_session2\ntower_session3")

    [ "$result" = "$expected" ]
}

@test "list_metadata: returns empty when no metadata files exist" {
    result=$(list_metadata)
    [ -z "$result" ]
}

# ============================================================================
# v2 format tests
# ============================================================================

@test "save_metadata: v2 format creates file with directory_path" {
    save_metadata "tower_v2-session" "/home/user/projects/app"

    grep -q "directory_path=/home/user/projects/app" "${CLAUDE_TOWER_METADATA_DIR}/tower_v2-session.meta"
}

@test "save_metadata: v2 format stores session_name" {
    save_metadata "tower_my-project" "/path/to/dir"

    grep -q "session_name=my-project" "${CLAUDE_TOWER_METADATA_DIR}/tower_my-project.meta"
}

@test "load_metadata: v2 format sets META_DIRECTORY_PATH" {
    cat > "${CLAUDE_TOWER_METADATA_DIR}/tower_v2-test.meta" << EOF
session_id=tower_v2-test
session_name=v2-test
directory_path=/custom/work/path
created_at=2026-02-07T10:00:00+09:00
EOF

    load_metadata "tower_v2-test"
    [ "$META_DIRECTORY_PATH" = "/custom/work/path" ]
}

# ============================================================================
# v1 backward compatibility tests (T052-T054)
# ============================================================================

@test "load_metadata: reads worktree_path as directory_path (v1 compat)" {
    # Create v1 format metadata with worktree_path
    cat > "${CLAUDE_TOWER_METADATA_DIR}/tower_v1-worktree.meta" << EOF
session_id=tower_v1-worktree
session_type=workspace
repository_path=/home/user/repos/main
worktree_path=/home/user/.claude-tower/worktrees/v1-worktree
source_commit=abc123
EOF

    load_metadata "tower_v1-worktree"

    # worktree_path should be mapped to META_DIRECTORY_PATH
    [ "$META_DIRECTORY_PATH" = "/home/user/.claude-tower/worktrees/v1-worktree" ]
}

@test "load_metadata: reads repository_path as fallback for directory_path (v1 compat)" {
    # Create v1 format metadata without worktree_path
    cat > "${CLAUDE_TOWER_METADATA_DIR}/tower_v1-simple.meta" << EOF
session_id=tower_v1-simple
session_type=simple
repository_path=/home/user/repos/simple-project
source_commit=def456
EOF

    load_metadata "tower_v1-simple"

    # repository_path should be fallback for META_DIRECTORY_PATH
    [ "$META_DIRECTORY_PATH" = "/home/user/repos/simple-project" ]
}

@test "load_metadata: worktree_path takes priority over repository_path (v1 compat)" {
    # Create v1 format metadata with both paths
    cat > "${CLAUDE_TOWER_METADATA_DIR}/tower_v1-both.meta" << EOF
session_id=tower_v1-both
session_type=workspace
repository_path=/home/user/repos/main
worktree_path=/home/user/.claude-tower/worktrees/v1-both
source_commit=xyz789
EOF

    load_metadata "tower_v1-both"

    # worktree_path should take priority
    [ "$META_DIRECTORY_PATH" = "/home/user/.claude-tower/worktrees/v1-both" ]
}

@test "load_metadata: v2 directory_path takes priority over v1 fields" {
    # Create mixed format (shouldn't happen, but test priority)
    cat > "${CLAUDE_TOWER_METADATA_DIR}/tower_mixed.meta" << EOF
session_id=tower_mixed
session_name=mixed
directory_path=/v2/directory/path
worktree_path=/v1/worktree/path
repository_path=/v1/repo/path
EOF

    load_metadata "tower_mixed"

    # v2 directory_path should be used
    [ "$META_DIRECTORY_PATH" = "/v2/directory/path" ]
}
