#!/usr/bin/env bats
# Unit tests for claude-sessions.sh (jsonl-derived session info)

load 'test_helper'

UUID_A="11111111-1111-4111-8111-111111111111"
UUID_B="22222222-2222-4222-8222-222222222222"

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "find_session_jsonl: finds transcript in slug dir" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    run find_session_jsonl "$UUID_A"
    [ "$status" -eq 0 ]
    [ "$output" = "$f" ]
}

@test "find_session_jsonl: returns 1 when not found" {
    run find_session_jsonl "$UUID_B"
    [ "$status" -eq 1 ]
}

@test "find_session_jsonl: does not match subagent transcripts" {
    mkdir -p "${CLAUDE_PROJECTS_DIR}/-home-user-proj/${UUID_A}/subagents"
    echo '{}' > "${CLAUDE_PROJECTS_DIR}/-home-user-proj/${UUID_A}/subagents/agent-x.jsonl"
    run find_session_jsonl "agent-x"
    [ "$status" -eq 1 ]
}

@test "get_session_cwd: extracts first cwd value" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    run get_session_cwd "$f"
    [ "$status" -eq 0 ]
    [ "$output" = "/home/user/proj" ]
}

@test "get_session_cwd: first occurrence wins when cwd changes mid-session" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    printf '{"type":"user","cwd":"/home/user/proj/sub"}\n' >> "$f"
    run get_session_cwd "$f"
    [ "$output" = "/home/user/proj" ]
}

@test "get_session_cwd: handles cwd with spaces" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/my proj")
    run get_session_cwd "$f"
    [ "$output" = "/home/user/my proj" ]
}

@test "get_session_cwd: returns 1 when transcript has no cwd line" {
    local f
    f=$(create_empty_jsonl "-home-user-proj" "$UUID_A")
    run get_session_cwd "$f"
    [ "$status" -eq 1 ]
}

@test "session_has_messages: true for real session" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    run session_has_messages "$f"
    [ "$status" -eq 0 ]
}

@test "session_has_messages: false for empty shell" {
    local f
    f=$(create_empty_jsonl "-home-user-proj" "$UUID_A")
    run session_has_messages "$f"
    [ "$status" -eq 1 ]
}

@test "get_session_activity: returns jsonl mtime" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    run get_session_activity "$f"
    [ "$output" = "$(stat -c %Y -- "$f")" ]
}

@test "get_session_activity: subagent mtime wins when newer" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    local sub="${CLAUDE_PROJECTS_DIR}/-home-user-proj/${UUID_A}/subagents"
    mkdir -p "$sub"
    echo '{}' > "${sub}/agent-x.jsonl"
    run get_session_activity "$f"
    [ "$output" = "$(stat -c %Y -- "${sub}/agent-x.jsonl")" ]
}

@test "get_session_activity: background task output mtime wins when newer" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    local tasks="${TMPDIR:-/tmp}/claude-$(id -u)/-home-user-proj/${UUID_A}/tasks"
    mkdir -p "$tasks"
    echo x > "${tasks}/a.output"
    run get_session_activity "$f"
    [ "$output" = "$(stat -c %Y -- "${tasks}/a.output")" ]
    rm -rf "${TMPDIR:-/tmp}/claude-$(id -u)/-home-user-proj"
}

@test "is_session_busy: true for freshly touched transcript" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    run is_session_busy "$f"
    [ "$status" -eq 0 ]
}

@test "is_session_busy: false for old transcript" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    run is_session_busy "$f"
    [ "$status" -eq 1 ]
}
