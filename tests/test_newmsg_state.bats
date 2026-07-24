#!/usr/bin/env bats
# Unread-as-a-state: a stopped session with new output renders as the
# newmsg state (✱ left icon), not a separate right-column mark.

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "get_state_icon: newmsg renders as ✱" {
    run get_state_icon "newmsg"
    [ "$output" = "✱" ]
}

@test "STATE_NEWMSG constant is defined" {
    [ "$STATE_NEWMSG" = "newmsg" ]
}

# navigator-list.sh sources common.sh (readonly), fresh bash per pattern.
_run_nav() {
    run bash -c '
        export CLAUDE_TOWER_METADATA_DIR="'"$CLAUDE_TOWER_METADATA_DIR"'"
        export CLAUDE_PROJECTS_DIR="'"$CLAUDE_PROJECTS_DIR"'"
        export CLAUDE_TOWER_NAV_SOCKET="newmsg-nav-$$"
        export CLAUDE_TOWER_SESSION_SOCKET="newmsg-sess-$$"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/navigator-list.sh"
        set +e
        tput() { case "$1" in cols) echo 80 ;; lines) echo 24 ;; ed) printf "" ;; *) command tput "$@" 2>/dev/null ;; esac; }
        _session_label() { echo "t-${1#tower_}"; }
        _session_dir() { echo "/proj/demo"; }
        mark_session_seen() { :; }
        init_session_seen() { :; }
        count_unregistered_processes_in_dir() { echo 0; }
        '"$1"'
    '
}

@test "build_session_list: a stopped unread session promotes to the newmsg ✱ icon" {
    _run_nav '
        list_all_sessions() { echo "tower_x:active"; }
        is_session_unread() { return 0; }
        build_session_list
        printf "%s\n" "${SESSION_DISPLAYS[0]}" | sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"✱ t-x"* ]]
}

@test "build_session_list: newmsg suppresses the plain ▶ active icon" {
    _run_nav '
        list_all_sessions() { echo "tower_x:active"; }
        is_session_unread() { return 0; }
        build_session_list
        printf "%s\n" "${SESSION_DISPLAYS[0]}" | sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g"
    '
    [ "$status" -eq 0 ]
    [[ "$output" != *"▶"* ]]
}

@test "build_session_list: a busy session never becomes newmsg (it is working, not stopped)" {
    _run_nav '
        list_all_sessions() { echo "tower_x:busy"; }
        is_session_unread() { return 0; }
        find_session_jsonl() { echo /dev/null; }
        count_active_subagents() { echo 0; }
        build_session_list
        printf "%s\n" "${SESSION_DISPLAYS[0]}"
    '
    [ "$status" -eq 0 ]
    # Busy stays the spinner placeholder, not the ✱ state.
    [[ "$output" == *"@@SPIN@@"* ]]
}

@test "build_session_list: subagent count still lands in the right column, unread aside" {
    _run_nav '
        list_all_sessions() { echo "tower_x:busy"; }
        is_session_unread() { return 1; }
        find_session_jsonl() { echo /dev/null; }
        count_active_subagents() { echo 3; }
        build_session_list
        printf "%s\n" "${SESSION_DISPLAYS[0]}" | sed -E "s/\x1b\[[0-9;?]*[a-zA-Z]//g"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚙3"* ]]
}
