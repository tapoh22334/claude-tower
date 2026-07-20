#!/usr/bin/env bats
# Session dashboard: project grouping, external-process visibility,
# subagent badges, fork/new-in-dir starts.
# Library-level tests run in-process (setup_test_env isolates the dirs);
# navigator-list.sh tests run in a fresh bash (it sources common.sh, and
# re-sourcing hits readonly collisions).

load 'test_helper'

UUID_A="11111111-1111-4111-8111-111111111111"
UUID_B="22222222-2222-4222-8222-222222222222"

setup() {
    source_common
    setup_test_env
    export CLAUDE_LIVE_SESSIONS_DIR="${BATS_TEST_TMPDIR}/live-sessions"
    mkdir -p "$CLAUDE_LIVE_SESSIONS_DIR"
}

teardown() {
    teardown_test_env
}

_write_live_json() {
    local pid="$1" sid="$2" cwd="$3"
    printf '{"pid":%s,"sessionId":"%s","cwd":"%s","status":"idle"}\n' \
        "$pid" "$sid" "$cwd" > "${CLAUDE_LIVE_SESSIONS_DIR}/${pid}.json"
}

@test "list_live_claude_processes: lists live pids, skips dead ones" {
    _write_live_json "$$" "$UUID_A" "/home/x/proj"
    _write_live_json "99999999" "$UUID_B" "/home/x/other"
    run list_live_claude_processes
    [ "$status" -eq 0 ]
    [[ "$output" == *"$UUID_A"* ]]
    [[ "$output" != *"$UUID_B"* ]]
    [[ "$output" == *"/home/x/proj"* ]]
}

@test "is_claude_process_alive: true only for a live session id" {
    _write_live_json "$$" "$UUID_A" "/home/x/proj"
    run is_claude_process_alive "$UUID_A"
    [ "$status" -eq 0 ]
    run is_claude_process_alive "$UUID_B"
    [ "$status" -ne 0 ]
}

@test "count_unregistered_processes_in_dir: counts live unregistered claude in a dir" {
    _write_live_json "$$" "$UUID_A" "/home/x/proj"
    run count_unregistered_processes_in_dir "/home/x/proj"
    [ "$output" = "1" ]
    # Registering the session removes it from the count
    create_mock_metadata "tower_${UUID_A}"
    run count_unregistered_processes_in_dir "/home/x/proj"
    [ "$output" = "0" ]
}

@test "get_display_state: registered session with live process is external, not dormant" {
    local f
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "$HOME")
    create_mock_metadata "tower_${UUID_A}"
    touch -d "2020-01-01 00:00:00" "$f"

    run get_display_state "tower_${UUID_A}"
    [ "$output" = "dormant" ]

    _write_live_json "$$" "$UUID_A" "$HOME"
    run get_display_state "tower_${UUID_A}"
    [ "$output" = "external" ]
}

@test "count_active_subagents: counts only recently-touched subagent transcripts" {
    local f sub
    f=$(create_mock_jsonl "-home-user-proj" "$UUID_A" "$HOME")
    sub="${CLAUDE_PROJECTS_DIR}/-home-user-proj/${UUID_A}/subagents"
    mkdir -p "$sub"
    echo '{}' > "${sub}/fresh.jsonl"
    echo '{}' > "${sub}/stale.jsonl"
    touch -d "2020-01-01 00:00:00" "${sub}/stale.jsonl"
    run count_active_subagents "$f"
    [ "$output" = "1" ]
}

@test "list_project_dirs: dedupes and orders by newest transcript" {
    # A dir under TMPDIR would be filtered out — use one under TEST_DIR.
    local newdir="${TEST_DIR}/tmp/proj-b"
    mkdir -p "$newdir"
    local old
    old=$(create_mock_jsonl "-dir-a" "$UUID_A" "$HOME")
    create_mock_jsonl "-dir-b" "$UUID_B" "$newdir" > /dev/null
    touch -d "2020-01-01 00:00:00" "$old"
    run list_project_dirs
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$newdir" ]
    [ "${lines[1]}" = "$HOME" ]
}

@test "get_state_icon: external renders as ◇" {
    run get_state_icon "external"
    [ "$output" = "◇" ]
}

# ---------------------------------------------------------------------------
# navigator-list.sh: grouping renderer (fresh bash; sources the script)
# ---------------------------------------------------------------------------

# $1 = snippet run after sourcing navigator-list.sh with stubbed deps
_run_nav() {
    local snippet="$1"
    run bash -c '
        export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'"
        export CLAUDE_PROJECTS_DIR="'"$CLAUDE_PROJECTS_DIR"'"
        export CLAUDE_LIVE_SESSIONS_DIR="'"$CLAUDE_LIVE_SESSIONS_DIR"'"
        export CLAUDE_TOWER_NAV_SOCKET="dash-test-nav-$$"
        export CLAUDE_TOWER_SESSION_SOCKET="dash-test-sess-$$"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/navigator-list.sh"
        set +e
        '"$snippet"'
    '
}

@test "build_session_list: groups sessions by dir with one header per group" {
    _run_nav '
        list_all_sessions() {
            echo "tower_a1:active"
            echo "tower_b1:active"
            echo "tower_a2:dormant"
        }
        _session_label() { echo "label-$1"; }
        _session_dir() {
            case "$1" in
                tower_a1|tower_a2) echo "/proj/alpha" ;;
                *) echo "/proj/beta" ;;
            esac
        }
        mark_session_seen() { :; }
        init_session_seen() { :; }
        is_session_unread() { return 1; }
        count_unregistered_processes_in_dir() { echo 0; }
        build_session_list
        printf "ids:%s\n" "${SESSION_IDS[*]}"
        for h in "${SESSION_HEADERS[@]}"; do printf "hdr:[%s]\n" "$h"; done
    '
    [ "$status" -eq 0 ]
    # alpha sessions regrouped together, first-appearance group order
    [[ "$output" == *"ids:tower_a1 tower_a2 tower_b1"* ]]
    # exactly two non-empty headers: alpha then beta
    local hdrs
    hdrs=$(grep -c "hdr:\[.\+\]" <<<"$output" || true)
    [ "$hdrs" -eq 2 ]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"beta"* ]]
}

@test "build_session_list: group header carries unmanaged-process badge" {
    _run_nav '
        list_all_sessions() { echo "tower_a1:active"; }
        _session_label() { echo "x"; }
        _session_dir() { echo "/proj/alpha"; }
        mark_session_seen() { :; }
        init_session_seen() { :; }
        is_session_unread() { return 1; }
        count_unregistered_processes_in_dir() { echo 2; }
        build_session_list
        printf "%s\n" "${SESSION_HEADERS[0]}"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚡2"* ]]
}

@test "render_list: frame with headers never exceeds terminal height" {
    _run_nav '
        tput() { case "$1" in lines) echo 12 ;; cols) echo 80 ;; ed) printf "" ;; *) command tput "$@" 2>/dev/null ;; esac; }
        get_nav_focus() { echo "list"; }
        SESSION_IDS=(); SESSION_DISPLAYS=(); SESSION_DIRS=(); SESSION_HEADERS=()
        for ((i = 0; i < 15; i++)); do
            SESSION_IDS+=("tower_s$i")
            SESSION_DISPLAYS+=("row $i")
            SESSION_DIRS+=("/proj/p$((i % 5))")
            if ((i % 3 == 0)); then SESSION_HEADERS+=("▍p$((i % 5))"); else SESSION_HEADERS+=(""); fi
        done
        BROKEN_START=9
        raw=$(render_list 0)
        # grep -c "" counts every line, including an unterminated last one
        nl=$(printf "%s" "$raw" | grep -c "" || true)
        echo "lines=$nl"
    '
    [ "$status" -eq 0 ]
    local lines="${output##*lines=}"
    [ "$lines" -le 12 ]
}

@test "render_list: hidden count in +N more counts sessions, not header lines" {
    _run_nav '
        tput() { case "$1" in lines) echo 10 ;; cols) echo 80 ;; ed) printf "" ;; *) command tput "$@" 2>/dev/null ;; esac; }
        get_nav_focus() { echo "list"; }
        SESSION_IDS=(); SESSION_DISPLAYS=(); SESSION_DIRS=(); SESSION_HEADERS=()
        for ((i = 0; i < 20; i++)); do
            SESSION_IDS+=("tower_s$i")
            SESSION_DISPLAYS+=("row $i")
            SESSION_DIRS+=("/proj/p$i")
            SESSION_HEADERS+=("▍p$i")
        done
        BROKEN_START=-1
        render_list 0
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"more"* ]]
    # 10-line terminal: budget 6 body lines -> 5 shown -> at most 3 session
    # rows visible -> at least 17 hidden sessions reported
    [[ "$output" =~ \+1[7-9]\ more ]]
}

@test "navigator-list.sh: f and N keys are wired" {
    run grep -c -E "^                (f|N)\)" "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
    [ "$output" = "2" ]
    run grep -A 1 "^                f)" "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
    [[ "$output" == *"fork_session_here"* ]]
    run grep -A 1 "^                N)" "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
    [[ "$output" == *"new_session_pick_dir"* ]]
}

@test "restore_selected: refuses to resume an external session" {
    run grep -A 4 'get_display_state "\$selected".*==.*external' "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"return 0"* ]]
}

# ---------------------------------------------------------------------------
# session-add.sh: --fork-dir / --new-in-dir
# ---------------------------------------------------------------------------

@test "session-add.sh: --fork-dir starts a session in the given dir and prints the id" {
    run bash -c '
        export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'"
        export CLAUDE_PROJECTS_DIR="'"$CLAUDE_PROJECTS_DIR"'"
        export CLAUDE_TOWER_SESSION_SOCKET="dash-test-sess-$$"
        # Source everything up to (not including) main, then stub the
        # heavyweight session starter.
        eval "$(sed "/^main() {/,\$d" "'"$PROJECT_ROOT"'/tmux-plugin/scripts/session-add.sh" | sed "s/^set -uo pipefail//")" 2>/dev/null
        PRINT_ID=1
        start_claude_session() { echo "started:$1:$2" >&2; return 0; }
        start_session_in_dir "'"$BATS_TEST_TMPDIR"'"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"tower_"* ]]
    [[ "$output" == *"started:tower_"* ]]
    [[ "$output" == *":${BATS_TEST_TMPDIR}"* ]]
}

@test "session-add.sh: --fork-dir fails cleanly on a missing directory" {
    run "$PROJECT_ROOT/tmux-plugin/scripts/session-add.sh" --fork-dir /nonexistent/dir/xyz --print-id
    [ "$status" -ne 0 ]
}
