#!/usr/bin/env bats
# get_display_state / restore_session logic (tmux stubbed)

load 'test_helper'

UUID_A="11111111-1111-4111-8111-111111111111"

setup() {
    source_common
    setup_test_env
    # Stub tmux: no sessions exist unless MOCK_TMUX_HAS=1
    MOCK_TMUX_HAS=0
    session_tmux() {
        if [[ "$1" == "has-session" ]]; then
            [[ "$MOCK_TMUX_HAS" == "1" ]]
            return
        fi
        return 0
    }
}

teardown() {
    teardown_test_env
}

@test "get_display_state: busy when tmux exists and transcript fresh" {
    MOCK_TMUX_HAS=1
    create_mock_jsonl "-home-user-proj" "$UUID_A" "$HOME" > /dev/null
    run get_display_state "tower_${UUID_A}"
    [ "$output" = "busy" ]
}

@test "get_display_state: active when tmux exists and transcript old" {
    MOCK_TMUX_HAS=1
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "$HOME")
    touch -d "2020-01-01 00:00:00" "$f"
    run get_display_state "tower_${UUID_A}"
    [ "$output" = "active" ]
}

@test "get_display_state: dormant when only meta, cwd exists" {
    create_mock_jsonl "-home-user-proj" "$UUID_A" "$HOME" > /dev/null
    create_mock_metadata "tower_${UUID_A}"
    run get_display_state "tower_${UUID_A}"
    [ "$output" = "dormant" ]
}

@test "get_display_state: dead when cwd directory is gone" {
    create_mock_jsonl "-home-user-proj" "$UUID_A" "/nonexistent/dir/xyz" > /dev/null
    create_mock_metadata "tower_${UUID_A}"
    run get_display_state "tower_${UUID_A}"
    [ "$output" = "dead" ]
}

@test "get_display_state: lost when jsonl is gone" {
    create_mock_metadata "tower_${UUID_A}"
    run get_display_state "tower_${UUID_A}"
    [ "$output" = "lost" ]
}

@test "get_display_state: empty when neither tmux nor meta" {
    run get_display_state "tower_${UUID_A}"
    [ -z "$output" ]
}

@test "restore_session: fails with guidance when jsonl gone" {
    create_mock_metadata "tower_${UUID_A}"
    run restore_session "tower_${UUID_A}"
    [ "$status" -eq 1 ]
}

@test "restore_session: fails when cwd gone" {
    create_mock_jsonl "-home-user-proj" "$UUID_A" "/nonexistent/dir/xyz" > /dev/null
    create_mock_metadata "tower_${UUID_A}"
    run restore_session "tower_${UUID_A}"
    [ "$status" -eq 1 ]
}

@test "start_claude_session: rejects missing directory" {
    run start_claude_session "tower_${UUID_A}" "/nonexistent/dir/xyz" "new"
    [ "$status" -eq 1 ]
}
