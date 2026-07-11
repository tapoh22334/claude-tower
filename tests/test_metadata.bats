#!/usr/bin/env bats
# Unit tests for the minimal metadata registry in common.sh

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "save_metadata: creates metadata file" {
    save_metadata "tower_11111111-1111-4111-8111-111111111111"
    [ -f "${CLAUDE_TOWER_METADATA_DIR}/tower_11111111-1111-4111-8111-111111111111.meta" ]
}

@test "save_metadata: stores created_at" {
    save_metadata "tower_test"
    grep -q "^created_at=" "${CLAUDE_TOWER_METADATA_DIR}/tower_test.meta"
}

@test "save_metadata: stores session_name when given" {
    save_metadata "tower_test" "my-feature"
    grep -q "^session_name=my-feature$" "${CLAUDE_TOWER_METADATA_DIR}/tower_test.meta"
}

@test "save_metadata: omits session_name when not given" {
    save_metadata "tower_test"
    ! grep -q "^session_name=" "${CLAUDE_TOWER_METADATA_DIR}/tower_test.meta"
}

@test "save_metadata: writes no legacy keys" {
    save_metadata "tower_test" "name"
    ! grep -q -E "^(session_type|repository_path|source_commit|worktree_path|branch_name)=" \
        "${CLAUDE_TOWER_METADATA_DIR}/tower_test.meta"
}

@test "load_metadata: returns 1 when file missing" {
    run load_metadata "tower_nope"
    [ "$status" -eq 1 ]
}

@test "load_metadata: sets META_SESSION_NAME and META_CREATED_AT" {
    save_metadata "tower_test" "my-feature"
    load_metadata "tower_test"
    [ "$META_SESSION_NAME" = "my-feature" ]
    [ -n "$META_CREATED_AT" ]
}

@test "load_metadata: ignores unknown keys from old-format files" {
    cat > "${CLAUDE_TOWER_METADATA_DIR}/tower_old.meta" << 'EOF'
session_id=tower_old
session_type=worktree
created_at=2025-01-01T00:00:00
repository_path=/some/repo
worktree_path=/some/worktree
EOF
    load_metadata "tower_old"
    [ "$META_CREATED_AT" = "2025-01-01T00:00:00" ]
    [ -z "$META_SESSION_NAME" ]
}

@test "has_metadata: true after save" {
    save_metadata "tower_test"
    has_metadata "tower_test"
}

@test "delete_metadata: removes file" {
    save_metadata "tower_test"
    delete_metadata "tower_test"
    ! has_metadata "tower_test"
}
