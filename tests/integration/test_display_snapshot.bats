#!/usr/bin/env bats
# Snapshot-based display tests
# Uses tmux capture-pane to verify visual output of the actual Navigator
# list pane (navigator-list.sh), against the 5-state model:
#   ● busy / ▶ active / ○ dormant / ✗ dead / ? lost
# Compares output against expected patterns (not exact match)

load '../test_helper'

# Test tmux sockets
NAV_SOCKET="ct-display-nav"
SESSION_SOCKET="ct-display-session"

setup_file() {
    export TMUX_TMPDIR="/tmp/claude-tower-display-test"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"

    # Sessions on the session server (TMUX= to allow nesting)
    TMUX= tmux -L "$SESSION_SOCKET" new-session -d -s "tower_display_a" -c /tmp 2>/dev/null || true
    TMUX= tmux -L "$SESSION_SOCKET" new-session -d -s "tower_display_b" -c /tmp 2>/dev/null || true
    TMUX= tmux -L "$SESSION_SOCKET" new-session -d -s "tower_display_c" -c /tmp 2>/dev/null || true
}

teardown_file() {
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
    rm -rf "/tmp/claude-tower-display-test" 2>/dev/null || true
}

setup() {
    # Set env vars BEFORE sourcing (TOWER_NAV_SOCKET/TOWER_SESSION_SOCKET are readonly)
    export CLAUDE_TOWER_NAV_SOCKET="$NAV_SOCKET"
    export CLAUDE_TOWER_SESSION_SOCKET="$SESSION_SOCKET"
    source_common
    setup_test_env
    ensure_nav_state_dir
    cleanup_nav_state
}

teardown() {
    TMUX= tmux -L "$NAV_SOCKET" kill-session -t "$TOWER_NAV_SESSION" 2>/dev/null || true
    cleanup_nav_state
    teardown_test_env
}

# Helper to strip ANSI codes for pattern matching
strip_ansi() {
    sed 's/\x1b\[[0-9;]*m//g'
}

# ============================================================================
# Data-layer tests (list_all_sessions / get_state_icon) - fast, no capture-pane
# ============================================================================

@test "display: list_all_sessions output contains session names" {
    tmux() { command tmux -L "$SESSION_SOCKET" "$@"; }
    export -f tmux

    run list_all_sessions

    [ "$status" -eq 0 ]
    [[ "$output" == *"tower_display_a"* ]]
    [[ "$output" == *"tower_display_b"* ]]
    [[ "$output" == *"tower_display_c"* ]]
}

@test "display: list_all_sessions output has consistent id:state format" {
    tmux() { command tmux -L "$SESSION_SOCKET" "$@"; }
    export -f tmux

    run list_all_sessions
    [ "$status" -eq 0 ]

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local colon_count
        colon_count=$(echo "$line" | tr -cd ':' | wc -c)
        [ "$colon_count" -eq 1 ]
    done <<< "$output"
}

@test "display: state icons match the 5-state model" {
    run get_state_icon "busy"
    [ "$output" = "●" ]

    run get_state_icon "active"
    [ "$output" = "▶" ]

    run get_state_icon "dormant"
    [ "$output" = "○" ]

    run get_state_icon "dead"
    [ "$output" = "✗" ]

    run get_state_icon "lost"
    [ "$output" = "?" ]

    # Unknown states return ?
    run get_state_icon "unknown"
    [ "$output" = "?" ]
}

@test "display: dormant sessions included in list" {
    tmux() { command tmux -L "$SESSION_SOCKET" "$@"; }
    export -f tmux

    create_mock_metadata "tower_dormant_display" "workspace"

    run list_all_sessions

    [ "$status" -eq 0 ]
    [[ "$output" == *"tower_dormant_display"* ]]
    # No jsonl/cwd for this session, so get_display_state returns "" (not
    # registered enough to resolve cwd) -- but has_metadata is true and
    # find_session_jsonl will fail -> "lost". Assert it appears with a state,
    # not blank.
    [[ "$output" == *"tower_dormant_display:"* ]]
}

@test "display: empty session list handled gracefully" {
    tmux() {
        if [[ "$1" == "list-sessions" ]]; then
            return 1
        fi
        command tmux -L "$SESSION_SOCKET" "$@"
    }
    export -f tmux

    run list_all_sessions
    [ "$status" -eq 0 ]
}

@test "display: color constants render as real ANSI escapes via echo -e" {
    # common.sh's C_* constants are double-quoted literals (e.g.
    # C_RED="\033[0;31m"), not $'...' ANSI-C-quoted strings like navigator's
    # NAV_C_* — so the variable itself holds the four characters
    # backslash-0-3-3, not a raw ESC byte. That's fine as long as every
    # caller renders them with `echo -e` / `printf '%b'`, which re-interprets
    # \033 as an escape (handle_error/handle_warning/handle_success do).
    # This test verifies the end-to-end rendering, not the raw variable.
    local rendered
    rendered=$(echo -e "${C_RED}x${C_RESET}")
    [[ "$rendered" == *$'\033'* ]]

    rendered=$(echo -e "${C_GREEN}x${C_RESET}")
    [[ "$rendered" == *$'\033'* ]]
}

@test "display: NAV colors in navigator-list use \$'...' syntax" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"

    run grep "NAV_C_" "$script"
    [ "$status" -eq 0 ]
    [[ "$output" == *"\$'"* ]]
}

@test "display: long session names truncated safely" {
    local long_name="tower_this_is_a_very_long_session_name_that_exceeds_display_width"

    local sanitized
    sanitized=$(sanitize_name "$long_name")

    [ ${#sanitized} -le 64 ]
}

# ============================================================================
# Real capture-pane tests: render the actual Navigator list pane
# ============================================================================

# Boots a real navigator-list.sh in a tmux pane on $NAV_SOCKET, pointed at
# sessions/metadata/jsonl fixtures we control, and returns the rendered
# screen text (ANSI-stripped) via stdout.
render_navigator_list() {
    TMUX= tmux -L "$NAV_SOCKET" new-session -d -s "$TOWER_NAV_SESSION" -x 80 -y 24 \
        -e "CLAUDE_TOWER_NAV_SOCKET=$NAV_SOCKET" \
        -e "CLAUDE_TOWER_SESSION_SOCKET=$SESSION_SOCKET" \
        -e "CLAUDE_TOWER_METADATA_DIR=$CLAUDE_TOWER_METADATA_DIR" \
        -e "CLAUDE_PROJECTS_DIR=$CLAUDE_PROJECTS_DIR" \
        "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"

    # Give the render loop time to draw its first frame
    sleep 1

    TMUX= tmux -L "$NAV_SOCKET" capture-pane -t "$TOWER_NAV_SESSION:0.0" -p | strip_ansi
}

@test "display: rendered list shows header and footer with new keybindings" {
    TMUX= tmux -L "$SESSION_SOCKET" new-session -d -s "tower_render_active" -c /tmp 2>/dev/null || true

    run render_navigator_list
    [ "$status" -eq 0 ]

    [[ "$output" == *"Sessions"* ]]
    # Footer reflects the current 5-state-era keybindings (n:add, D:del,
    # r:resume - not the removed R:restore-all)
    [[ "$output" == *"j/k:nav"* ]]
    [[ "$output" == *"Enter:attach"* ]]
    [[ "$output" == *"i:input"* ]]
    [[ "$output" == *"n:add"* ]]
    [[ "$output" == *"D:del"* ]]
    [[ "$output" == *"r:resume"* ]]
    [[ "$output" == *"q:quit"* ]]

    TMUX= tmux -L "$SESSION_SOCKET" kill-session -t "tower_render_active" 2>/dev/null || true
}

@test "display: rendered list shows active session with cwd-basename label" {
    local claude_id="11111111-1111-1111-1111-111111111111"
    local cwd="$BATS_TEST_TMPDIR/proj-alpha"
    mkdir -p "$cwd"
    create_mock_jsonl "-tmp-proj-alpha" "$claude_id" "$cwd" >/dev/null

    create_mock_metadata "tower_${claude_id}"
    TMUX= tmux -L "$SESSION_SOCKET" new-session -d -s "tower_${claude_id}" -c "$cwd" 2>/dev/null

    run render_navigator_list
    [ "$status" -eq 0 ]

    # Row label = basename of cwd, not the raw session id
    [[ "$output" == *"proj-alpha"* ]]

    TMUX= tmux -L "$SESSION_SOCKET" kill-session -t "tower_${claude_id}" 2>/dev/null || true
}

@test "display: rendered list shows dead/lost separator before unrecoverable rows" {
    # dead: metadata + jsonl exist, but cwd dir is gone
    local dead_id="22222222-2222-2222-2222-222222222222"
    local gone_cwd="$BATS_TEST_TMPDIR/will-be-removed"
    mkdir -p "$gone_cwd"
    create_mock_jsonl "-tmp-will-be-removed" "$dead_id" "$gone_cwd" >/dev/null
    create_mock_metadata "tower_${dead_id}"
    rmdir "$gone_cwd"

    # An active session too, so the list has a normal section before the separator
    TMUX= tmux -L "$SESSION_SOCKET" new-session -d -s "tower_render_active2" -c /tmp 2>/dev/null || true

    run render_navigator_list
    [ "$status" -eq 0 ]

    [[ "$output" == *"unrecoverable"* ]]
}

@test "display: rendered list shows lost session with ? icon" {
    # lost: metadata exists, jsonl does not
    create_mock_metadata "tower_33333333-3333-3333-3333-333333333333"

    run render_navigator_list
    [ "$status" -eq 0 ]

    [[ "$output" == *"?"* ]]
    [[ "$output" == *"unrecoverable"* ]]
}

@test "display: help screen documents current keybindings, not removed ones" {
    TMUX= tmux -L "$NAV_SOCKET" new-session -d -s "$TOWER_NAV_SESSION" -x 80 -y 24 \
        -e "CLAUDE_TOWER_NAV_SOCKET=$NAV_SOCKET" \
        -e "CLAUDE_TOWER_SESSION_SOCKET=$SESSION_SOCKET" \
        "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
    sleep 1

    TMUX= tmux -L "$NAV_SOCKET" send-keys -t "$TOWER_NAV_SESSION:0.0" "?"
    sleep 0.5

    local output
    output=$(TMUX= tmux -L "$NAV_SOCKET" capture-pane -t "$TOWER_NAV_SESSION:0.0" -p | strip_ansi)

    [[ "$output" == *"Navigator Help"* ]]
    [[ "$output" == *"Resume selected dormant session"* ]]
    # 'R' (restore-all) was removed by the redesign; the help screen must
    # not advertise it as a single-key binding anymore.
    [[ "$output" != *"R          "* ]]
}
