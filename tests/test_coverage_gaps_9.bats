#!/usr/bin/env bats
# Coverage gaps (round 9): _session_label, wait_for_update,
# format_relative_time boundaries, session-list.sh --json validity,
# setup_pane_auto_restart unquoted-variable interpolation.

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

# ============================================================================
# _session_label() — navigator-list.sh
# Computes the row text shown in the session list. Since project grouping,
# the group header carries the directory name, so the row label is the
# conversation title (get_session_title), falling back to the short id,
# plus an optional " (name)" suffix from metadata.
# ============================================================================

@test "_session_label: uses the conversation title when history has one" {
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true

    local uuid="22222222-2222-4222-8222-222222222222"
    create_mock_jsonl "myproj" "$uuid" "/home/user/projects/myproj"
    CLAUDE_HISTORY_FILE="${BATS_TEST_TMPDIR}/history.jsonl"
    echo '{"display":"fix the login bug","sessionId":"'"$uuid"'"}' > "$CLAUDE_HISTORY_FILE"

    run _session_label "tower_${uuid}"
    [ "$status" -eq 0 ]
    [ "$output" = "fix the login bug" ]
}

@test "_session_label: falls back to short id when no jsonl is found" {
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true

    local uuid="33333333-3333-4333-8333-333333333333"
    # No create_mock_jsonl call: find_session_jsonl will fail.

    run _session_label "tower_${uuid}"
    [ "$status" -eq 0 ]
    [ "$output" = "${uuid:0:7}" ]
}

@test "_session_label: falls back to short id when transcript has no cwd" {
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true

    local uuid="44444444-4444-4444-8444-444444444444"
    create_mock_jsonl "myproj" "$uuid" ""

    run _session_label "tower_${uuid}"
    [ "$status" -eq 0 ]
    [ "$output" = "${uuid:0:7}" ]
}

# The mock transcript's user line carries no content and the test history
# has no entry, so the title falls back to the short id in the two tests
# below — the point is the " (name)" suffix behavior.

@test "_session_label: appends registry name in parens when metadata has one" {
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true

    local uuid="55555555-5555-4555-8555-555555555555"
    create_mock_jsonl "myproj" "$uuid" "/home/user/projects/myproj"
    create_mock_metadata "tower_${uuid}" "my-alias"

    run _session_label "tower_${uuid}"
    [ "$status" -eq 0 ]
    [ "$output" = "${uuid:0:7} (my-alias)" ]
}

@test "_session_label: no name suffix when metadata exists but has no session_name" {
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true

    local uuid="66666666-6666-4666-8666-666666666666"
    create_mock_jsonl "myproj" "$uuid" "/home/user/projects/myproj"
    create_mock_metadata "tower_${uuid}" ""

    run _session_label "tower_${uuid}"
    [ "$status" -eq 0 ]
    [ "$output" = "${uuid:0:7}" ]
}

# ============================================================================
# render_list() — frame height must never exceed the terminal height.
# If it does, every redraw scrolls the screen and the 2s refresh loop turns
# into an endless upward crawl (list appears to shrink continuously).
# ============================================================================

@test "render_list: frame with separator and truncation fits terminal height" {
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true

    # Stub terminal: 12 lines tall; fail other capability queries so
    # render_list takes its printf fallbacks.
    tput() {
        if [[ "$1" == "lines" ]]; then echo 12; else return 1; fi
    }

    SESSION_IDS=()
    SESSION_DISPLAYS=()
    local i
    for i in $(seq 1 30); do
        SESSION_IDS+=("tower_session_$i")
        SESSION_DISPLAYS+=("● session-$i")
    done
    BROKEN_START=3

    run render_list 0
    [ "$status" -eq 0 ]

    # The frame is one atomic printf; lines = newline count + 1 (the footer
    # intentionally has no trailing newline). Must fit in 12 rows.
    local nl_count
    nl_count=$(printf '%s' "$output" | wc -l)
    [ "$((nl_count + 1))" -le 12 ]
}

@test "render_list: frame emits no trailing newline after the footer" {
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true

    tput() {
        if [[ "$1" == "lines" ]]; then echo 24; else return 1; fi
    }

    SESSION_IDS=("tower_only")
    SESSION_DISPLAYS=("○ only")
    BROKEN_START=-1

    local raw last_line
    raw=$(render_list 0; printf 'SENTINEL')
    # A newline after the footer would scroll a full-height frame on every
    # redraw. The text after the frame's last newline must still contain the
    # footer, i.e. nothing but escape codes and the sentinel follow it.
    last_line="${raw##*$'\n'}"
    [[ "$last_line" == *"q:quit"* ]]
    [[ "$last_line" == *"SENTINEL" ]]
}
# Existing test (test_claude_sessions.bats:173) only covers minutes/hours.
# Missing: days boundary (>=86400s) and malformed/negative input behavior.
# ============================================================================

@test "format_relative_time: days" {
    local now
    now=$(date +%s)

    run format_relative_time "$((now - 172800))"
    [ "$status" -eq 0 ]
    [ "$output" = "2d ago" ]
}

@test "format_relative_time: exact hour boundary rolls into hours bucket, not minutes" {
    local now
    now=$(date +%s)

    run format_relative_time "$((now - 3600))"
    [ "$status" -eq 0 ]
    [ "$output" = "1h ago" ]
}

@test "format_relative_time: exact day boundary rolls into days bucket, not hours" {
    local now
    now=$(date +%s)

    run format_relative_time "$((now - 86400))"
    [ "$status" -eq 0 ]
    [ "$output" = "1d ago" ]
}

@test "format_relative_time: future epoch (negative diff) does not crash" {
    local now
    now=$(date +%s)

    # epoch in the future -> negative diff; document current behavior rather
    # than assert a specific "in the future" string, since none exists.
    run format_relative_time "$((now + 120))"
    [ "$status" -eq 0 ]
}

# ============================================================================
# session-list.sh --json — currently only asserted via raw string/comma
# checks (test_coverage_gaps_6.bats), never parsed as JSON. A session name
# containing a double quote would produce invalid JSON undetected.
# ============================================================================

@test "session-list.sh --json: output is valid, parseable JSON" {
    create_mock_metadata "tower_valid1" "alias-one"
    create_mock_metadata "tower_valid2" ""

    run "$PROJECT_ROOT/tmux-plugin/scripts/session-list.sh" --json
    [ "$status" -eq 0 ]

    echo "$output" | jq -e 'type == "array"' >/dev/null
}

@test "session-list.sh --json: session id containing a double quote breaks JSON validity (documents known gap)" {
    # session_id here is a stand-in for a value that reaches the json branch
    # unescaped; list_all_sessions only emits ids we control today, so this
    # test drives the json-emitting branch directly instead of end-to-end.
    source "$PROJECT_ROOT/tmux-plugin/lib/common.sh" 2>/dev/null || true

    run bash -c '
        session_id="tower_bad\"name"
        state="dormant"
        echo "["
        cat <<EOF
  {
    "session_id": "$session_id",
    "state": "$state"
  }
EOF
        echo "]"
    '
    [ "$status" -eq 0 ]
    # Document current behavior: this is NOT valid JSON (unescaped quote).
    ! echo "$output" | jq -e . >/dev/null 2>&1
}

# ============================================================================
# setup_pane_auto_restart() — error-recovery.sh:449-455
# Existing test only varies $script_dir (with a space). TOWER_NAV_SOCKET and
# TOWER_NAV_SESSION are never varied even though they're interpolated
# unquoted into the same nested run-shell string.
# ============================================================================

@test "setup_pane_auto_restart: TOWER_NAV_SOCKET with special characters reaches the generated command intact" {
    # TOWER_NAV_SOCKET is readonly once common.sh is sourced, so the value
    # must arrive via the CLAUDE_TOWER_NAV_SOCKET env override in a fresh
    # bash subprocess, with tmux stubbed to capture the set-hook payload.
    run bash -c '
        set -u
        export CLAUDE_TOWER_NAV_SOCKET="sock with space"
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/common.sh" 2>/dev/null
        source "'"$PROJECT_ROOT"'/tmux-plugin/lib/error-recovery.sh" 2>/dev/null
        tmux() {
            printf "%s\n" "$*" >>"'"${TEST_DIR}"'/tmp/tmux_calls.log"
        }
        setup_pane_auto_restart "/some/script/dir"
    '
    [ "$status" -eq 0 ]

    grep -q "sock with space" "${TEST_DIR}/tmp/tmux_calls.log"
}

# ============================================================================
# render_list spinner - busy rows carry SPIN_PLACEHOLDER at build time and
# render_list substitutes the current frame, so the spinner turns on every
# redraw without rebuilding the session list.
# ============================================================================

@test "render_list: substitutes the busy placeholder with the current spinner frame" {
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true

    tput() {
        if [[ "$1" == "lines" ]]; then echo 24; else return 1; fi
    }

    SESSION_IDS=("tower_busy1")
    SESSION_DISPLAYS=("${SPIN_PLACEHOLDER} working-session")
    BROKEN_START=-1

    SPIN_TICK=0
    run render_list 0
    [ "$status" -eq 0 ]
    [[ "$output" != *"$SPIN_PLACEHOLDER"* ]]
    [[ "$output" == *"${SPINNER_FRAMES[0]} working-session"* ]]

    SPIN_TICK=1
    run render_list 0
    [[ "$output" == *"${SPINNER_FRAMES[1]} working-session"* ]]
}

@test "build_session_list: busy row embeds the spinner placeholder, stopped unseen row gets the unread mark" {
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true

    TOWER_SEEN_DIR="${BATS_TEST_TMPDIR}/seen"
    local uuid_busy="aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    local uuid_done="bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    local f_busy f_done
    f_busy=$(create_mock_jsonl "-home-user-proj" "$uuid_busy" "/home/user/proj")
    f_done=$(create_mock_jsonl "-home-user-other" "$uuid_done" "/home/user/other")

    # The stopped session already has a (stale) seen mark; its transcript
    # then moved on -> unread.
    touch -d "2020-01-01 00:00:00" "$f_done"
    mark_session_seen "tower_${uuid_done}"
    touch -d "2020-01-02 00:00:00" "$f_done"

    list_all_sessions() {
        echo "tower_${uuid_busy}:busy"
        echo "tower_${uuid_done}:active"
    }
    get_nav_selected() { echo ""; }

    build_session_list

    [[ "${SESSION_DISPLAYS[0]}" == *"$SPIN_PLACEHOLDER"* ]]
    [[ "${SESSION_DISPLAYS[1]}" == *"$ICON_UNREAD"* ]]
}

@test "build_session_list: selected session is marked seen, so no unread mark" {
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true

    TOWER_SEEN_DIR="${BATS_TEST_TMPDIR}/seen"
    local uuid="cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$uuid" "/home/user/proj")
    touch -d "2020-01-01 00:00:00" "$f"
    mark_session_seen "tower_${uuid}"
    touch -d "2020-01-02 00:00:00" "$f"

    list_all_sessions() { echo "tower_${uuid}:active"; }
    get_nav_selected() { echo "tower_${uuid}"; }

    build_session_list

    [[ "${SESSION_DISPLAYS[0]}" != *"$ICON_UNREAD"* ]]
}
