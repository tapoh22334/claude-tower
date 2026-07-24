#!/usr/bin/env bats
# Unit tests for fork detection (claude-sessions.sh)

load 'test_helper'

PARENT="cccccccc-1111-4111-8111-111111111111"
FORK="dddddddd-2222-4222-8222-222222222222"
SOLO="eeeeeeee-3333-4333-8333-333333333333"

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "find_fork_parent: returns parent sessionId for a fork" {
    create_fork_pair_jsonl "-home-user-proj" "$PARENT" "$FORK" "/home/user/proj" >/dev/null
    run find_fork_parent "$FORK"
    [ "$status" -eq 0 ]
    [ "$output" = "$PARENT" ]
}

@test "find_fork_parent: returns 1 for an independent session (no shared uuids)" {
    # SOLO has its own uuids; another session shares none.
    local dir="${CLAUDE_PROJECTS_DIR}/-home-user-proj"
    mkdir -p "$dir"
    printf '{"type":"user","cwd":"/p","sessionId":"%s","uuid":"11110000-0000-4000-8000-000000000001"}\n' "$SOLO" >"${dir}/${SOLO}.jsonl"
    printf '{"type":"user","cwd":"/p","sessionId":"other","uuid":"99990000-0000-4000-8000-000000000009"}\n' >"${dir}/99999999-9999-4999-8999-999999999999.jsonl"
    run find_fork_parent "$SOLO"
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "find_fork_parent: returns 1 when the transcript is missing" {
    run find_fork_parent "00000000-0000-4000-8000-000000000000"
    [ "$status" -eq 1 ]
}

@test "find_fork_parent: does not match a NEWER sibling as parent" {
    create_fork_pair_jsonl "-home-user-proj" "$PARENT" "$FORK" "/home/user/proj" >/dev/null
    # Asking for the PARENT must not return the (newer) fork.
    run find_fork_parent "$PARENT"
    [ "$status" -eq 1 ]
}

@test "list_fork_sessions: lists an unregistered fork with its parent and pid" {
    create_fork_pair_jsonl "-home-user-proj" "$PARENT" "$FORK" "/home/user/proj" >/dev/null
    # Stub the live-process source: the fork is live at pid 4242.
    list_live_claude_processes() {
        printf '%s\t%s\t%s\n' "$FORK" "4242" "/home/user/proj"
    }
    # Nothing is registered in Tower.
    has_metadata() { return 1; }
    run list_fork_sessions "/home/user/proj"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\t%s\t%s' "$FORK" "$PARENT" "4242")" ]
}

@test "list_fork_sessions: skips forks already registered in Tower" {
    create_fork_pair_jsonl "-home-user-proj" "$PARENT" "$FORK" "/home/user/proj" >/dev/null
    list_live_claude_processes() { printf '%s\t%s\t%s\n' "$FORK" "4242" "/home/user/proj"; }
    has_metadata() { return 0; }   # everything is registered
    run list_fork_sessions "/home/user/proj"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "list_fork_sessions: skips live processes with no fork parent" {
    list_live_claude_processes() { printf '%s\t%s\t%s\n' "$SOLO" "4243" "/home/user/proj"; }
    has_metadata() { return 1; }
    run list_fork_sessions "/home/user/proj"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
