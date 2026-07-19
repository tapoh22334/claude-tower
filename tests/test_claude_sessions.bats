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

@test "list_addable_sessions: lists unregistered real sessions newest first" {
    local old new
    old=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "$HOME")
    new=$(create_mock_jsonl "-home-user-other" "$UUID_B" "$HOME")
    touch -d "2020-01-01 00:00:00" "$old"
    run list_addable_sessions
    [ "$status" -eq 0 ]
    [ "${lines[0]%%$'\t'*}" = "$UUID_B" ]
    [ "${lines[1]%%$'\t'*}" = "$UUID_A" ]
}

@test "list_addable_sessions: excludes registered sessions" {
    create_mock_jsonl "-home-user-proj" "$UUID_A" "$HOME" > /dev/null
    create_mock_metadata "tower_${UUID_A}"
    run list_addable_sessions
    [ -z "$output" ]
}

@test "list_addable_sessions: excludes empty shells" {
    create_empty_jsonl "-home-user-proj" "$UUID_A" > /dev/null
    run list_addable_sessions
    [ -z "$output" ]
}

@test "list_addable_sessions: excludes sessions with missing cwd" {
    create_mock_jsonl "-home-user-proj" "$UUID_A" "/nonexistent/dir/xyz" > /dev/null
    run list_addable_sessions
    [ -z "$output" ]
}

@test "list_addable_sessions: excludes tmp-dir internal sessions" {
    create_mock_jsonl "-tmp-something" "$UUID_A" "${TMPDIR:-/tmp}/whatever" > /dev/null
    mkdir -p "${TMPDIR:-/tmp}/whatever"
    run list_addable_sessions
    [ -z "$output" ]
    rmdir "${TMPDIR:-/tmp}/whatever" 2>/dev/null || true
}

@test "list_addable_sessions: skips non-uuid jsonl files" {
    mkdir -p "${CLAUDE_PROJECTS_DIR}/-home-user-proj"
    echo '{"type":"user","cwd":"'"$HOME"'"}' > "${CLAUDE_PROJECTS_DIR}/-home-user-proj/notauuid.jsonl"
    run list_addable_sessions
    [ -z "$output" ]
}

@test "get_session_title: returns the session's first (oldest) prompt from history.jsonl" {
    CLAUDE_HISTORY_FILE="${BATS_TEST_TMPDIR}/history.jsonl"
    {
        echo '{"display":"first prompt","pastedContents":{},"sessionId":"11111111-1111-4111-8111-111111111111"}'
        echo '{"display":"second prompt","pastedContents":{},"sessionId":"11111111-1111-4111-8111-111111111111"}'
    } > "$CLAUDE_HISTORY_FILE"
    run get_session_title "11111111-1111-4111-8111-111111111111"
    [ "$status" -eq 0 ]
    [ "$output" = "first prompt" ]
}

@test "get_session_title: returns 1 when the session has no history entry" {
    CLAUDE_HISTORY_FILE="${BATS_TEST_TMPDIR}/history.jsonl"
    echo '{"display":"someone else","sessionId":"99999999-9999-4999-8999-999999999999"}' > "$CLAUDE_HISTORY_FILE"
    run get_session_title "11111111-1111-4111-8111-111111111111"
    [ "$status" -ne 0 ]
}

@test "get_session_title: falls back to the transcript's first user message when absent from history" {
    CLAUDE_HISTORY_FILE="${BATS_TEST_TMPDIR}/no-such-history.jsonl"
    local uuid="22222222-2222-4222-8222-222222222222"
    local dir="${CLAUDE_PROJECTS_DIR}/-home-user-proj"
    mkdir -p "$dir"
    printf '%s\n' '{"type":"user","cwd":"/home/user/proj","message":{"role":"user","content":"headless prompt here"}}' \
        > "${dir}/${uuid}.jsonl"
    run get_session_title "$uuid"
    [ "$status" -eq 0 ]
    [ "$output" = "headless prompt here" ]
}

@test "get_session_title: fallback handles array-form content blocks via their text field" {
    CLAUDE_HISTORY_FILE="${BATS_TEST_TMPDIR}/no-such-history.jsonl"
    local uuid="33333333-3333-4333-8333-333333333333"
    local dir="${CLAUDE_PROJECTS_DIR}/-home-user-proj"
    mkdir -p "$dir"
    printf '%s\n' '{"type":"user","cwd":"/home/user/proj","message":{"role":"user","content":[{"type":"text","text":"block form prompt"}]}}' \
        > "${dir}/${uuid}.jsonl"
    run get_session_title "$uuid"
    [ "$status" -eq 0 ]
    [ "$output" = "block form prompt" ]
}

@test "get_session_title: returns 1 when neither history nor a transcript exists" {
    CLAUDE_HISTORY_FILE="${BATS_TEST_TMPDIR}/no-such-history.jsonl"
    run get_session_title "11111111-1111-4111-8111-111111111111"
    [ "$status" -ne 0 ]
}

@test "format_relative_time: minutes and hours" {
    local now
    now=$(date +%s)
    run format_relative_time "$((now - 120))"
    [ "$output" = "2m ago" ]
    run format_relative_time "$((now - 7200))"
    [ "$output" = "2h ago" ]
    run format_relative_time "$((now - 172800))"
    [ "$output" = "2d ago" ]
}
