#!/usr/bin/env bats
# How the full-screen views (Tile, Tail) hand the user back (#37).
#
# A view runs as a window inside a real tower_* session. Its old exit ran
# `tmux attach-session` from inside that pane, which put a client inside the
# session it was attached to: the Navigator came up nested, and opening a view
# again from there attached the session to itself — the shrinking-pane loop.
# The exit must instead detach the OUTER client (the person's terminal) with
# -E so the next attach runs outside every pane, then let the script exit so
# the view window closes.

load 'test_helper'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# Stub both servers. session server: this window lives in tower_x; two
# clients look at tower_x — /dev/pts/9 (a Navigator view pane's nested client,
# must never be chosen) and /dev/pts/3 (the person). nav server: one pane whose
# tty is /dev/pts/9.
_stubs='
    session_tmux() {
        case "$1" in
            display-message) echo "tower_x" ;;
            list-clients) printf "/dev/pts/9 200\n/dev/pts/3 100\n" ;;
            has-session) [[ "$3" == tower_caller ]] ;;
            list-sessions) printf "tower_x\ntower_caller\n" ;;
            *) echo "SESSION_TMUX $*" ;;
        esac
    }
    nav_tmux() {
        case "$1" in
            list-panes) echo "/dev/pts/9" ;;
            *) echo "NAV_TMUX $*" ;;
        esac
    }
    tmux() { echo "BARE_TMUX $*"; }
'

@test "view exit: returning to the Navigator detaches the outer client with -E, never attaches in-pane" {
    run bash -c "
        source '$PROJECT_ROOT/tmux-plugin/lib/common.sh'
        set +e
        $_stubs
        view_return_to_navigator
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"SESSION_TMUX detach-client -t /dev/pts/3 -E "*"attach-session -t 'navigator'"* ]]
    [[ "$output" != *"BARE_TMUX"* ]]
    [[ "$output" != *"/dev/pts/9 -E"* ]]
}

@test "view exit: the Navigator view pane's own nested client is never the one detached" {
    # Only the nested client is attached (the person's client is gone): no
    # candidate, so the exit does nothing and just lets the window close.
    run bash -c "
        source '$PROJECT_ROOT/tmux-plugin/lib/common.sh'
        set +e
        $_stubs
        session_tmux() { case \"\$1\" in display-message) echo tower_x ;; list-clients) echo '/dev/pts/9 200' ;; *) echo \"SESSION_TMUX \$*\" ;; esac; }
        view_return_to_navigator
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"detach-client"* ]]
}

@test "view exit: quitting hands the outer client to the caller session, still via detach -E" {
    run bash -c "
        source '$PROJECT_ROOT/tmux-plugin/lib/common.sh'
        set +e
        $_stubs
        set_nav_caller tower_caller
        view_quit_navigator
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"SESSION_TMUX detach-client -t /dev/pts/3 -E "*"attach-session -t 'tower_caller'"* ]]
    [[ "$output" != *"BARE_TMUX attach"* ]]
}

@test "view exit: quitting never picks the session this view runs in as the fallback target" {
    # No caller recorded; the fallback used to be `list-sessions | head -1`,
    # which is tower_x — the very session hosting this window (self-attach).
    run bash -c "
        source '$PROJECT_ROOT/tmux-plugin/lib/common.sh'
        set +e
        $_stubs
        view_quit_navigator
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"attach-session -t 'tower_x'"* ]]
}

@test "tile.sh and tail-view.sh no longer attach from inside their pane" {
    run grep -n 'attach-session' "$PROJECT_ROOT/tmux-plugin/scripts/tile.sh" "$PROJECT_ROOT/tmux-plugin/scripts/tail-view.sh"
    [ "$status" -ne 0 ]
}
