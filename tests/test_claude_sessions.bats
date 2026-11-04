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

@test "get_session_activity: background agent output (symlink) wins when newer" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    local agent="${BATS_TEST_TMPDIR}/agent-x.jsonl"
    echo '{}' > "$agent"
    local tasks="${TMPDIR:-/tmp}/claude-$(id -u)/-home-user-proj/${UUID_A}/tasks"
    mkdir -p "$tasks"
    ln -s "$agent" "${tasks}/a.output"
    # The link was made when the agent started; the agent wrote since.
    touch -h -d "2020-01-02 00:00:00" "${tasks}/a.output"
    touch -d "2020-01-03 00:00:00" "$agent"
    run get_session_activity "$f"
    rm -rf "${TMPDIR:-/tmp}/claude-$(id -u)/-home-user-proj"
    [ "$output" = "$(stat -c %Y -- "$agent")" ]
}

@test "get_session_activity: background shell output does not count" {
    # A dev server or a stuck polling loop writes its task output for as
    # long as it runs, with Claude itself idle at the prompt.
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    local tasks="${TMPDIR:-/tmp}/claude-$(id -u)/-home-user-proj/${UUID_A}/tasks"
    mkdir -p "$tasks"
    echo x > "${tasks}/a.output"
    run get_session_activity "$f"
    rm -rf "${TMPDIR:-/tmp}/claude-$(id -u)/-home-user-proj"
    [ "$output" = "$(stat -c %Y -- "$f")" ]
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

@test "is_session_busy: pane timer wins over a stale transcript" {
    # The regression this guards: Claude writes the transcript only when a
    # message completes, so a long tool call ages the mtime out while the
    # session is plainly still working.
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    run is_session_busy "$f" "tower_${UUID_A}" '✻ Pontificating… (12s · ↓ 1.4k tokens)'
    [ "$status" -eq 0 ]
}

@test "is_session_busy: pane timer past a minute still reads as working" {
    # The timer switches from "45s" to "1m 19s"; matching only [0-9]+s
    # would drop exactly the long turns this fix exists for.
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    run is_session_busy "$f" "tower_${UUID_A}" '· Pontificating… (1m 19s · ↓ 3.8k tokens)'
    [ "$status" -eq 0 ]
}

@test "is_session_busy: idle pane falls back to the transcript verdict" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    run is_session_busy "$f" "tower_${UUID_A}" '❯ '
    [ "$status" -eq 1 ]
}

@test "pane_shows_working: quoted 'esc to interrupt' is not a working signal" {
    # A transcript discussing the old heuristic used to match itself.
    run pane_shows_working "tower_${UUID_A}" 'the esc to interrupt hint'
    [ "$status" -eq 1 ]
}

# --- background agents (#114) ---
# Real captures: tests/fixtures/panes/README.md.
_pane() { cat "${BATS_TEST_DIRNAME}/fixtures/panes/$1.txt"; }

@test "pane_shows_working: a background agent listed under the prompt is work" {
    # Main waits at the prompt, so there is no "(… tokens)" counter; the
    # agent's own row ("5m 1s · ↓ 69.6k tokens", no parentheses) is the
    # only sign on screen, and the transcript can stay silent for minutes.
    run pane_shows_working "tower_${UUID_A}" "$(_pane main-idle-agent-running)"
    [ "$status" -eq 0 ]
}

@test "pane_shows_working: only a background shell left running is not work (#85)" {
    run pane_shows_working "tower_${UUID_A}" "$(_pane background-shell-only)"
    [ "$status" -eq 1 ]
}

@test "pane_shows_working: a finished agent's 'Waiting for' line in scrollback is not work" {
    local text
    text=$(_pane background-shell-only | sed '1i ✻ Waiting for 1 background agent to finish')
    run pane_shows_working "tower_${UUID_A}" "$text"
    [ "$status" -eq 1 ]
}

@test "pane_shows_working: main's counter survives a long agent list below the prompt" {
    # The agent list grows one row per agent under the prompt box. Read as
    # "the last 12 lines", ten rows pushed main's token counter off (#88).
    local text i
    text=$(_pane main-working-no-agent)
    text+=$'\n  ● main'
    for i in 1 2 3 4 5 6 7 8 9 10; do
        text+=$'\n'"  ◯ general-purpose  step ${i}   ${i}s · ↓ 1.0k tok"
    done
    # The rows end in "tok", not "tokens": only main's counter can match.
    run pane_shows_working "tower_${UUID_A}" "$text"
    [ "$status" -eq 0 ]
}

@test "pane_agent_count: counts the agent rows under the prompt, not main" {
    run pane_agent_count "tower_${UUID_A}" "$(_pane main-idle-agent-running)"
    [ "$output" = "1" ]
    run pane_agent_count "tower_${UUID_A}" "$(_pane main-working-with-agent)"
    [ "$output" = "1" ]
}

@test "pane_agent_count: zero without an agent list" {
    run pane_agent_count "tower_${UUID_A}" "$(_pane main-working-no-agent)"
    [ "$output" = "0" ]
    run pane_agent_count "tower_${UUID_A}" "$(_pane background-shell-only)"
    [ "$output" = "0" ]
}

@test "pane_agent_count: an agent row quoted in the transcript above the prompt is not counted" {
    local text
    text=$(_pane background-shell-only |
        sed '1i \ \ ◯ tower-reviewer  Writing m.sh   5m 1s · ↓ 69.6k tokens')
    run pane_agent_count "tower_${UUID_A}" "$text"
    [ "$output" = "0" ]
}

@test "is_session_busy: a running background agent beats a silent transcript" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    run is_session_busy "$f" "tower_${UUID_A}" "$(_pane main-idle-agent-running)"
    [ "$status" -eq 0 ]
}

@test "is_session_busy: without pre-fetched text it reads the pane itself" {
    # The production call passes no text. It used to forward "${3-}", an
    # empty string taken as the pane, so no pane was ever captured and busy
    # was mtime alone. Every test above passes text and could not see that.
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    PANE_FIXTURE="${BATS_TEST_DIRNAME}/fixtures/panes/main-working-no-agent.txt"
    session_tmux() { [[ "$1" == capture-pane ]] && cat "$PANE_FIXTURE"; }
    run is_session_busy "$f" "tower_${UUID_A}"
    [ "$status" -eq 0 ]
}

@test "count_active_subagents: the pane's agent list counts even when no transcript moved" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    run count_active_subagents "$f" "tower_${UUID_A}" "$(_pane main-idle-agent-running)"
    [ "$output" = "1" ]
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

@test "unread: activity past the seen mark reads as unread" {
    TOWER_SEEN_DIR="${BATS_TEST_TMPDIR}/seen"
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    mark_session_seen "tower_${UUID_A}"
    touch -d "2020-01-02 00:00:00" "$f"
    run is_session_unread "tower_${UUID_A}"
    [ "$status" -eq 0 ]
}

@test "unread: freshly seen session is not unread" {
    TOWER_SEEN_DIR="${BATS_TEST_TMPDIR}/seen"
    create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj" > /dev/null
    mark_session_seen "tower_${UUID_A}"
    run is_session_unread "tower_${UUID_A}"
    [ "$status" -eq 1 ]
}

@test "unread: session with no seen mark is not unread" {
    TOWER_SEEN_DIR="${BATS_TEST_TMPDIR}/seen"
    create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj" > /dev/null
    run is_session_unread "tower_${UUID_A}"
    [ "$status" -eq 1 ]
}

@test "unread: init_session_seen baselines once and never overwrites" {
    TOWER_SEEN_DIR="${BATS_TEST_TMPDIR}/seen"
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    init_session_seen "tower_${UUID_A}"
    # Transcript advances (session working); a second init must NOT re-mark
    # it seen - the busy->stop transition has to surface as unread.
    touch -d "2020-01-02 00:00:00" "$f"
    init_session_seen "tower_${UUID_A}"
    run is_session_unread "tower_${UUID_A}"
    [ "$status" -eq 0 ]
}

@test "unread: mark_session_seen without a transcript is a silent no-op" {
    TOWER_SEEN_DIR="${BATS_TEST_TMPDIR}/seen"
    run mark_session_seen "tower_${UUID_B}"
    [ "$status" -eq 0 ]
    [ ! -f "${TOWER_SEEN_DIR}/tower_${UUID_B}" ]
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

@test "pane_agent_count: works in the C locale too" {
    # bash's =~ is locale-dependent: in C, "─+" repeats only the last byte
    # of "─", the rule never matched, and the agent list went unseen.
    local text
    text="$(_pane main-idle-agent-running)"
    run env LC_ALL=C LANG=C bash -c '
        source "$1/tmux-plugin/lib/common.sh" 2>/dev/null
        pane_agent_count x "$2"' _ "$PROJECT_ROOT" "$text"
    [ "$output" = "1" ]
}

@test "pane_agent_count: a list left on screen after Claude exited is not counted" {
    # The tmux session is a shell, so the pane outlives Claude, last frame
    # included; the agent list is only live while it is the pane's bottom.
    local text
    text="$(_pane main-idle-agent-running)"$'\n''user@host:~/proj$ '
    run pane_agent_count "tower_${UUID_A}" "$text"
    [ "$output" = "0" ]
    run pane_shows_working "tower_${UUID_A}" "$text"
    [ "$status" -eq 1 ]
}

@test "count_active_subagents: with a session and no text it reads the pane itself" {
    # nav-build's call shape.
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "/home/user/proj")
    PANE_FIXTURE="${BATS_TEST_DIRNAME}/fixtures/panes/main-idle-agent-running.txt"
    session_tmux() { [[ "$1" == capture-pane ]] && cat "$PANE_FIXTURE"; }
    run count_active_subagents "$f" "tower_${UUID_A}"
    [ "$output" = "1" ]
}
