#!/usr/bin/env bats
# Unit tests for tower add command (User Story 1)

load 'test_helper'

setup() {
    source_common
    setup_test_env

    # Create a test directory for valid paths
    TEST_WORK_DIR="${TEST_DIR}/tmp/workdir"
    mkdir -p "$TEST_WORK_DIR"

    # Create a test file (not directory) for invalid path tests
    TEST_FILE="${TEST_DIR}/tmp/testfile.txt"
    touch "$TEST_FILE"
}

teardown() {
    teardown_test_env
}

# ============================================================================
# T014: Test file creation
# ============================================================================

@test "test_session_add.bats exists and is executable" {
    [ -f "${TEST_DIR}/test_session_add.bats" ]
}

# ============================================================================
# T015: tower add creates session with valid directory path
# ============================================================================

@test "create_session: creates session with valid directory" {
    # Mock session_tmux to avoid actual tmux calls
    session_tmux() {
        case "$1" in
            has-session) return 1 ;;  # Session doesn't exist
            new-session) return 0 ;;  # Session created
            capture-pane) echo "$ " ;;  # Shell ready
            send-keys) return 0 ;;    # Keys sent
        esac
    }
    export -f session_tmux

    run create_session "test-project" "$TEST_WORK_DIR"
    [ "$status" -eq 0 ]

    # Verify metadata was created
    [ -f "${CLAUDE_TOWER_METADATA_DIR}/tower_test-project.meta" ]
}

@test "create_session: saves v2 metadata format" {
    session_tmux() {
        case "$1" in
            has-session) return 1 ;;
            new-session) return 0 ;;
            capture-pane) echo "$ " ;;
            send-keys) return 0 ;;
        esac
    }
    export -f session_tmux

    create_session "my-session" "$TEST_WORK_DIR"

    # Check v2 format fields
    grep -q "session_id=tower_my-session" "${CLAUDE_TOWER_METADATA_DIR}/tower_my-session.meta"
    grep -q "session_name=my-session" "${CLAUDE_TOWER_METADATA_DIR}/tower_my-session.meta"
    grep -q "directory_path=${TEST_WORK_DIR}" "${CLAUDE_TOWER_METADATA_DIR}/tower_my-session.meta"
    grep -q "created_at=" "${CLAUDE_TOWER_METADATA_DIR}/tower_my-session.meta"
}

# ============================================================================
# T016: tower add with -n option uses custom session name
# ============================================================================

@test "create_session: uses custom name when provided" {
    session_tmux() {
        case "$1" in
            has-session) return 1 ;;
            new-session) return 0 ;;
            capture-pane) echo "$ " ;;
            send-keys) return 0 ;;
        esac
    }
    export -f session_tmux

    # Using custom name different from directory
    create_session "custom-name" "$TEST_WORK_DIR"

    [ -f "${CLAUDE_TOWER_METADATA_DIR}/tower_custom-name.meta" ]
    grep -q "session_name=custom-name" "${CLAUDE_TOWER_METADATA_DIR}/tower_custom-name.meta"
}

# ============================================================================
# T017: tower add fails if path does not exist
# ============================================================================

@test "create_session: fails if directory does not exist" {
    session_tmux() {
        case "$1" in
            has-session) return 1 ;;
        esac
    }
    export -f session_tmux

    run create_session "test-session" "/nonexistent/path/that/does/not/exist"
    [ "$status" -ne 0 ]
}

@test "_create_simple_session: fails with non-existent directory" {
    run _create_simple_session "tower_test" "test-name" "/path/does/not/exist"
    [ "$status" -ne 0 ]
}

# ============================================================================
# T018: tower add fails if path is not a directory
# ============================================================================

@test "_create_simple_session: fails if path is a file" {
    run _create_simple_session "tower_test" "test-name" "$TEST_FILE"
    [ "$status" -ne 0 ]
}

# ============================================================================
# T019: tower add fails if session name already exists
# ============================================================================

@test "create_session: fails if session already exists" {
    session_tmux() {
        case "$1" in
            has-session) return 0 ;;  # Session exists
        esac
    }
    export -f session_tmux

    run create_session "existing-session" "$TEST_WORK_DIR"
    [ "$status" -ne 0 ]
}

@test "create_session: fails if metadata already exists" {
    # Pre-create metadata for the session
    create_mock_metadata_v2 "tower_existing"

    session_tmux() {
        case "$1" in
            has-session) return 0 ;;  # Session exists
        esac
    }
    export -f session_tmux

    run create_session "existing" "$TEST_WORK_DIR"
    [ "$status" -ne 0 ]
}

# ============================================================================
# Helper functions for v2 metadata
# ============================================================================

# Create a mock v2 metadata file
create_mock_metadata_v2() {
    local session_id="$1"
    local directory_path="${2:-/mock/workdir}"
    local session_name="${session_id#tower_}"

    cat > "${CLAUDE_TOWER_METADATA_DIR}/${session_id}.meta" << EOF
session_id=${session_id}
session_name=${session_name}
directory_path=${directory_path}
created_at=$(date -Iseconds)
EOF
}

# ============================================================================
# save_metadata v2 format tests
# ============================================================================

@test "save_metadata: creates v2 format file" {
    save_metadata "tower_v2-test" "/path/to/workdir"

    [ -f "${CLAUDE_TOWER_METADATA_DIR}/tower_v2-test.meta" ]
}

@test "save_metadata: v2 format has session_id" {
    save_metadata "tower_test" "/path/to/dir"

    grep -q "session_id=tower_test" "${CLAUDE_TOWER_METADATA_DIR}/tower_test.meta"
}

@test "save_metadata: v2 format has session_name" {
    save_metadata "tower_my-project" "/path/to/dir"

    grep -q "session_name=my-project" "${CLAUDE_TOWER_METADATA_DIR}/tower_my-project.meta"
}

@test "save_metadata: v2 format has directory_path" {
    save_metadata "tower_test" "/custom/directory/path"

    grep -q "directory_path=/custom/directory/path" "${CLAUDE_TOWER_METADATA_DIR}/tower_test.meta"
}

@test "save_metadata: v2 format has created_at" {
    save_metadata "tower_test" "/path/to/dir"

    grep -q "created_at=" "${CLAUDE_TOWER_METADATA_DIR}/tower_test.meta"
}

# ============================================================================
# Input validation tests
# ============================================================================

@test "create_session: sanitizes session name" {
    session_tmux() {
        case "$1" in
            has-session) return 1 ;;
            new-session) return 0 ;;
            capture-pane) echo "$ " ;;
            send-keys) return 0 ;;
        esac
    }
    export -f session_tmux

    # Name with special characters should be sanitized
    run create_session "test!@#session" "$TEST_WORK_DIR"
    [ "$status" -eq 0 ]

    # The sanitized name should be used
    [ -f "${CLAUDE_TOWER_METADATA_DIR}/tower_testsession.meta" ]
}

@test "create_session: rejects empty name" {
    run create_session "" "$TEST_WORK_DIR"
    [ "$status" -ne 0 ]
}
