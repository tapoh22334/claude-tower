#!/usr/bin/env bats
# Wait-state detection: classify_pane_wait signatures, get_wait_state tiers,
# wait_since. Library-level, in-process (setup_test_env isolates dirs).

load 'test_helper'

UUID="11111111-1111-4111-8111-111111111111"

setup() {
    source_common
    setup_test_env
    export CLAUDE_LIVE_SESSIONS_DIR="${BATS_TEST_TMPDIR}/live-sessions"
    mkdir -p "$CLAUDE_LIVE_SESSIONS_DIR"
}

teardown() {
    teardown_test_env
}

# --- classify_pane_wait ----------------------------------------------------

@test "classify_pane_wait: 'esc to interrupt' is working, not waiting" {
    run classify_pane_wait "doing things… (esc to interrupt)"
    [ "$output" = "" ]
}

@test "classify_pane_wait: a [y/N] prompt is a permission wait" {
    run classify_pane_wait "Do you want to make this edit? [y/N]"
    [ "$output" = "permission" ]
}

@test "classify_pane_wait: 'Do you want' alone is a permission wait" {
    run classify_pane_wait "Do you want to proceed?"
    [ "$output" = "permission" ]
}

@test "classify_pane_wait: a numbered ❯ menu is a question wait" {
    run classify_pane_wait "$(printf '❯ 1. first\n  2. second')"
    [ "$output" = "question" ]
}

@test "classify_pane_wait: plain finished output is an input wait" {
    run classify_pane_wait "All done. Anything else?"
    [ "$output" = "input" ]
}

@test "classify_pane_wait: working takes precedence over a stray menu glyph" {
    run classify_pane_wait "$(printf '❯ 1. opt\nrunning (esc to interrupt)')"
    [ "$output" = "" ]
}

# --- get_wait_state tiers --------------------------------------------------
# session_tmux has-session must return false so the managed branch is
# skipped; these test the non-tmux tiers (external / dead / lost / dormant).

_no_tmux() {
    session_tmux() { return 1; }
    export -f session_tmux 2>/dev/null || true
}

@test "get_wait_state: registered session whose transcript is gone is an error" {
    create_mock_metadata "tower_${UUID}"
    # No transcript created -> find_session_jsonl fails -> lost -> error.
    session_tmux() { return 1; }
    run get_wait_state "tower_${UUID}"
    [ "$output" = "error" ]
}

@test "get_wait_state: registered session whose cwd is gone is an error" {
    create_mock_jsonl "-home-user-proj" "$UUID" "/nonexistent/gone/xyz" > /dev/null
    create_mock_metadata "tower_${UUID}"
    session_tmux() { return 1; }
    run get_wait_state "tower_${UUID}"
    [ "$output" = "error" ]
}

@test "get_wait_state: external live process (no managed pane) is a coarse input wait" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID" "$HOME")
    create_mock_metadata "tower_${UUID}"
    printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"idle"}\n' \
        "$$" "$UUID" "$HOME" > "${CLAUDE_LIVE_SESSIONS_DIR}/$$.json"
    session_tmux() { return 1; }
    run get_wait_state "tower_${UUID}"
    [ "$output" = "input" ]
}

@test "get_wait_state: dormant session (registered, not running) is not waiting" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID" "$HOME")
    create_mock_metadata "tower_${UUID}"
    # No live process file -> not external, cwd exists -> dormant -> "".
    session_tmux() { return 1; }
    run get_wait_state "tower_${UUID}"
    [ "$output" = "" ]
}

@test "get_wait_state: an unregistered session is not waiting" {
    session_tmux() { return 1; }
    run get_wait_state "tower_${UUID}"
    [ "$output" = "" ]
}

@test "get_wait_state: managed idle session is classified from the passed pane text" {
    create_mock_jsonl "-home-user-proj" "$UUID" "$HOME" > /dev/null
    # has-session true, transcript old so not busy; pane text passed in.
    local f
    f="${CLAUDE_PROJECTS_DIR}/-home-user-proj/${UUID}.jsonl"
    touch -d "2020-01-01" "$f"
    session_tmux() { [[ "$1" == "has-session" ]] && return 0; return 0; }
    run get_wait_state "tower_${UUID}" "Do you want to proceed? [y/N]"
    [ "$output" = "permission" ]
}

# --- wait_since ------------------------------------------------------------

@test "wait_since: returns the transcript activity epoch" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID" "$HOME")
    touch -d "2021-06-01 12:00:00" "$f"
    run wait_since "tower_${UUID}"
    [ "$output" = "$(stat -c %Y -- "$f")" ]
}

@test "wait_since: unknown session yields 0 (sorts as oldest)" {
    run wait_since "tower_${UUID}"
    [ "$output" = "0" ]
}
