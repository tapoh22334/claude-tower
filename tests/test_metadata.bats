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
# save_metadata() tests
# ============================================================================

@test "save_metadata: creates metadata file" {
    save_metadata "tower_test-session" "workspace" "/path/to/repo" "abc123"

    [ -f "${CLAUDE_TOWER_METADATA_DIR}/tower_test-session.meta" ]
}

@test "save_metadata: stores session_id" {
    save_metadata "tower_myproject" "workspace" "/path/to/repo" "abc123"

    grep -q "session_id=tower_myproject" "${CLAUDE_TOWER_METADATA_DIR}/tower_myproject.meta"
}

@test "save_metadata: stores session_type" {
    save_metadata "tower_myproject" "workspace" "/path/to/repo" "abc123"

    grep -q "session_type=workspace" "${CLAUDE_TOWER_METADATA_DIR}/tower_myproject.meta"
}

@test "save_metadata: stores repository_path" {
    save_metadata "tower_myproject" "workspace" "/path/to/repo" "abc123"

    grep -q "repository_path=/path/to/repo" "${CLAUDE_TOWER_METADATA_DIR}/tower_myproject.meta"
}

@test "save_metadata: stores source_commit" {
    save_metadata "tower_myproject" "workspace" "/path/to/repo" "abc123def456"

    grep -q "source_commit=abc123def456" "${CLAUDE_TOWER_METADATA_DIR}/tower_myproject.meta"
}

@test "save_metadata: stores worktree_path" {
    save_metadata "tower_myproject" "workspace" "/path/to/repo" "abc123"

    grep -q "worktree_path=${CLAUDE_TOWER_WORKTREE_DIR}/myproject" "${CLAUDE_TOWER_METADATA_DIR}/tower_myproject.meta"
}

@test "save_metadata: stores created_at timestamp" {
    save_metadata "tower_myproject" "workspace" "/path/to/repo" "abc123"

    grep -q "created_at=" "${CLAUDE_TOWER_METADATA_DIR}/tower_myproject.meta"
}

@test "save_metadata: handles simple session type" {
    save_metadata "tower_simple-session" "simple"

    grep -q "session_type=simple" "${CLAUDE_TOWER_METADATA_DIR}/tower_simple-session.meta"
}

@test "save_metadata: handles empty optional parameters" {
    save_metadata "tower_simple-session" "simple" "" ""

    grep -q "repository_path=$" "${CLAUDE_TOWER_METADATA_DIR}/tower_simple-session.meta"
    grep -q "source_commit=$" "${CLAUDE_TOWER_METADATA_DIR}/tower_simple-session.meta"
}

# ============================================================================
# load_metadata() tests
# ============================================================================

@test "load_metadata: returns 0 when file exists" {
    create_mock_metadata "tower_test"

    run load_metadata "tower_test"
    [ "$status" -eq 0 ]
}

@test "load_metadata: returns 1 when file does not exist" {
    run load_metadata "tower_nonexistent"
    [ "$status" -eq 1 ]
}

@test "load_metadata: sets META_SESSION_TYPE" {
    create_mock_metadata "tower_test" "workspace"

    load_metadata "tower_test"
    [ "$META_SESSION_TYPE" = "workspace" ]
}

@test "load_metadata: sets META_REPOSITORY_PATH" {
    create_mock_metadata "tower_test" "workspace" "/custom/repo/path"

    load_metadata "tower_test"
    [ "$META_REPOSITORY_PATH" = "/custom/repo/path" ]
}

@test "load_metadata: sets META_SOURCE_COMMIT" {
    create_mock_metadata "tower_test" "workspace" "/repo" "def456"

    load_metadata "tower_test"
    [ "$META_SOURCE_COMMIT" = "def456" ]
}

@test "load_metadata: sets META_WORKTREE_PATH" {
    create_mock_metadata "tower_test"

    load_metadata "tower_test"
    [ "$META_WORKTREE_PATH" = "${CLAUDE_TOWER_WORKTREE_DIR}/test" ]
}

@test "load_metadata: supports old 'mode' key for backwards compatibility" {
    # Create metadata with old key name
    cat > "${CLAUDE_TOWER_METADATA_DIR}/tower_old.meta" << EOF
session_id=tower_old
mode=workspace
repo_path=/old/repo
base_commit=old123
worktree_path=${CLAUDE_TOWER_WORKTREE_DIR}/old
EOF

    load_metadata "tower_old"
    [ "$META_SESSION_TYPE" = "workspace" ]
}

@test "load_metadata: supports old 'repo_path' key for backwards compatibility" {
    cat > "${CLAUDE_TOWER_METADATA_DIR}/tower_old.meta" << EOF
session_id=tower_old
mode=workspace
repo_path=/old/repo/path
base_commit=old123
worktree_path=${CLAUDE_TOWER_WORKTREE_DIR}/old
EOF

    load_metadata "tower_old"
    [ "$META_REPOSITORY_PATH" = "/old/repo/path" ]
}

@test "load_metadata: supports old 'base_commit' key for backwards compatibility" {
    cat > "${CLAUDE_TOWER_METADATA_DIR}/tower_old.meta" << EOF
session_id=tower_old
mode=workspace
repo_path=/old/repo
base_commit=oldcommit123
worktree_path=${CLAUDE_TOWER_WORKTREE_DIR}/old
EOF

    load_metadata "tower_old"
    [ "$META_SOURCE_COMMIT" = "oldcommit123" ]
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
