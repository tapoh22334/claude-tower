#!/usr/bin/env bats
# Coverage gaps: list_metadata, restart_session, send_to_session,
# start_claude_session (behavioral, beyond the "function exists" smoke tests
# in test_server_separation.bats)

load 'test_helper'

UUID_A="11111111-1111-4111-8111-111111111111"

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================================================
# list_metadata
# ============================================================================

@test "list_metadata: empty when no metadata files exist" {
    run list_metadata
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "list_metadata: lists a single session id without the .meta suffix" {
    create_mock_metadata "tower_${UUID_A}"
    run list_metadata
    [ "$output" = "tower_${UUID_A}" ]
}

@test "list_metadata: lists multiple session ids, one per line" {
    create_mock_metadata "tower_aaa"
    create_mock_metadata "tower_bbb"
    run list_metadata
    [ "$status" -eq 0 ]
    [[ "$output" == *"tower_aaa"* ]]
    [[ "$output" == *"tower_bbb"* ]]
    [ "$(echo "$output" | wc -l)" -eq 2 ]
}

# ============================================================================
# send_to_session (behavioral)
# ============================================================================

@test "send_to_session: fails when session is dormant" {
    create_mock_metadata "tower_${UUID_A}"
    session_tmux() { [[ "$1" == "has-session" ]] && return 1; return 0; }
    run send_to_session "tower_${UUID_A}" "echo hi"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not active"* ]]
}

@test "send_to_session: fails when session does not exist at all" {
    session_tmux() { [[ "$1" == "has-session" ]] && return 1; return 0; }
    run send_to_session "tower_${UUID_A}" "echo hi"
    [ "$status" -ne 0 ]
}

@test "send_to_session: sends input via session_tmux send-keys when active" {
    session_tmux() {
        if [[ "$1" == "has-session" ]]; then return 0; fi
        if [[ "$1" == "send-keys" ]]; then
            echo "send-keys $*" >> "$CLAUDE_TOWER_METADATA_DIR/sent.log"
            return 0
        fi
        return 0
    }
    run send_to_session "tower_${UUID_A}" "echo hi"
    [ "$status" -eq 0 ]
    grep -q "echo hi" "$CLAUDE_TOWER_METADATA_DIR/sent.log"
}

# ============================================================================
# restart_session (behavioral)
# ============================================================================

@test "restart_session: fails when session does not exist" {
    session_tmux() { [[ "$1" == "has-session" ]] && return 1; return 0; }
    run restart_session "tower_${UUID_A}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "restart_session: delegates to restore_session when dormant" {
    create_mock_metadata "tower_${UUID_A}"
    create_mock_jsonl "-home-user-proj" "$UUID_A" "/nonexistent/dir/xyz" > /dev/null
    session_tmux() { [[ "$1" == "has-session" ]] && return 1; return 0; }
    run restart_session "tower_${UUID_A}"
    # restore_session fails here (dead dir) but restart_session must have
    # routed through it rather than treating the session as active/exited.
    [ "$status" -ne 0 ]
    [[ "$output" == *"Directory not found"* ]]
}

@test "restart_session: sends Ctrl-C and re-issues claude --resume when active" {
    session_tmux() {
        case "$1" in
            has-session) return 0 ;;
            send-keys)
                echo "send-keys $*" >> "$CLAUDE_TOWER_METADATA_DIR/sent.log"
                return 0
                ;;
        esac
        return 0
    }
    run restart_session "tower_${UUID_A}"
    [ "$status" -eq 0 ]
    grep -q -- "--resume ${UUID_A}" "$CLAUDE_TOWER_METADATA_DIR/sent.log"
}

# ============================================================================
# start_claude_session (behavioral, happy paths)
# ============================================================================

@test "start_claude_session: no-ops with exit 0 when session already running" {
    session_tmux() { [[ "$1" == "has-session" ]] && return 0; return 0; }
    run start_claude_session "tower_${UUID_A}" "$HOME" "new"
    [ "$status" -eq 0 ]
    grep -q "already running" "${CLAUDE_TOWER_METADATA_DIR}/tower.log"
}

@test "start_claude_session: fails cleanly when new-session creation fails" {
    session_tmux() {
        case "$1" in
            has-session) return 1 ;;
            new-session) return 1 ;;
        esac
        return 0
    }
    run start_claude_session "tower_${UUID_A}" "$HOME" "new"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to create tmux session"* ]]
}

@test "start_claude_session: sends claude --session-id in new mode" {
    _wait_for_shell_ready() { return 0; }
    session_tmux() {
        case "$1" in
            has-session) return 1 ;;
            new-session) return 0 ;;
            send-keys)
                echo "send-keys $*" >> "$CLAUDE_TOWER_METADATA_DIR/sent.log"
                return 0
                ;;
        esac
        return 0
    }
    run start_claude_session "tower_${UUID_A}" "$HOME" "new"
    [ "$status" -eq 0 ]
    grep -q -- "--session-id ${UUID_A}" "$CLAUDE_TOWER_METADATA_DIR/sent.log"
}

@test "start_claude_session: sends claude --resume in resume mode" {
    _wait_for_shell_ready() { return 0; }
    session_tmux() {
        case "$1" in
            has-session) return 1 ;;
            new-session) return 0 ;;
            send-keys)
                echo "send-keys $*" >> "$CLAUDE_TOWER_METADATA_DIR/sent.log"
                return 0
                ;;
        esac
        return 0
    }
    run start_claude_session "tower_${UUID_A}" "$HOME" "resume"
    [ "$status" -eq 0 ]
    grep -q -- "--resume ${UUID_A}" "$CLAUDE_TOWER_METADATA_DIR/sent.log"
}
