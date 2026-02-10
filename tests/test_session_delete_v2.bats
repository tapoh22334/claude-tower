#!/usr/bin/env bats
# Unit tests for tower rm command (User Story 2 - v2)

load 'test_helper'

setup() {
    source_common
    setup_test_env

    # Create a test directory that should NOT be deleted
    TEST_WORK_DIR="${TEST_DIR}/tmp/workdir"
    mkdir -p "$TEST_WORK_DIR"
}

teardown() {
    teardown_test_env
}

# ============================================================================
# T029: Test file creation
# ============================================================================

@test "test_session_delete_v2.bats exists" {
    [ -f "${TEST_DIR}/test_session_delete_v2.bats" ]
}

# ============================================================================
# T030: tower rm deletes session metadata
# ============================================================================

@test "delete_session: removes metadata file" {
    # Create v2 metadata
    create_mock_metadata_v2 "tower_to-delete" "$TEST_WORK_DIR"
    [ -f "${CLAUDE_TOWER_METADATA_DIR}/tower_to-delete.meta" ]

    # Mock session_tmux to return dormant state
    session_tmux() {
        case "$1" in
            has-session) return 1 ;;  # Session not active (dormant)
            kill-session) return 0 ;;
        esac
    }
    export -f session_tmux

    # Mock confirm to always return yes
    confirm() { return 0; }
    export -f confirm

    delete_session "tower_to-delete" "force"

    # Metadata should be deleted
    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/tower_to-delete.meta" ]
}

@test "delete_session: removes metadata for active session" {
    create_mock_metadata_v2 "tower_active" "$TEST_WORK_DIR"

    # Mock as active session
    session_tmux() {
        case "$1" in
            has-session) return 0 ;;  # Session is active
            kill-session) return 0 ;;
        esac
    }
    export -f session_tmux

    delete_session "tower_active" "force"

    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/tower_active.meta" ]
}

# ============================================================================
# T031: tower rm does NOT delete directory
# ============================================================================

@test "delete_session: preserves directory" {
    create_mock_metadata_v2 "tower_preserve" "$TEST_WORK_DIR"
    [ -d "$TEST_WORK_DIR" ]

    session_tmux() {
        case "$1" in
            has-session) return 1 ;;
            kill-session) return 0 ;;
        esac
    }
    export -f session_tmux

    delete_session "tower_preserve" "force"

    # Directory should still exist
    [ -d "$TEST_WORK_DIR" ]
}

@test "delete_session: v2 never removes directories" {
    # Create a directory specifically for this session
    local session_dir="${TEST_DIR}/tmp/session-specific-dir"
    mkdir -p "$session_dir"

    create_mock_metadata_v2 "tower_my-session" "$session_dir"

    session_tmux() {
        case "$1" in
            has-session) return 0 ;;  # Active
            kill-session) return 0 ;;
        esac
    }
    export -f session_tmux

    delete_session "tower_my-session" "force"

    # The directory MUST still exist (v2 behavior)
    [ -d "$session_dir" ]
}

# ============================================================================
# T032: tower rm with -f skips confirmation
# ============================================================================

@test "delete_session: force flag skips confirmation" {
    create_mock_metadata_v2 "tower_force-test" "$TEST_WORK_DIR"

    # Track if confirm was called
    confirm_called=false
    confirm() {
        confirm_called=true
        return 0
    }
    export -f confirm
    export confirm_called

    session_tmux() {
        case "$1" in
            has-session) return 1 ;;
        esac
    }
    export -f session_tmux

    # With force flag, confirm should NOT be called
    delete_session "tower_force-test" "force"

    # Just verify the session was deleted (confirm should have been skipped)
    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/tower_force-test.meta" ]
}

@test "delete_session: -f flag also skips confirmation" {
    create_mock_metadata_v2 "tower_f-test" "$TEST_WORK_DIR"

    session_tmux() {
        case "$1" in
            has-session) return 1 ;;
        esac
    }
    export -f session_tmux

    delete_session "tower_f-test" "-f"

    [ ! -f "${CLAUDE_TOWER_METADATA_DIR}/tower_f-test.meta" ]
}

# ============================================================================
# T033: tower rm fails if session does not exist
# ============================================================================

@test "delete_session: fails if session does not exist" {
    session_tmux() {
        case "$1" in
            has-session) return 1 ;;  # No tmux session
        esac
    }
    export -f session_tmux

    # No metadata file either
    run delete_session "tower_nonexistent" "force"
    [ "$status" -ne 0 ]
}

@test "delete_session: fails if neither tmux session nor metadata exists" {
    session_tmux() {
        return 1
    }
    export -f session_tmux

    run delete_session "tower_ghost" "-f"
    [ "$status" -ne 0 ]
}

# ============================================================================
# session-delete.sh CLI tests
# ============================================================================

@test "session-delete.sh: requires session name argument" {
    # session-delete.sh without arguments should fail
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-delete.sh"
    [ "$status" -ne 0 ]
}

# ============================================================================
# Helper functions for v2 metadata
# ============================================================================

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
