#!/usr/bin/env bats
# Regression tests for Tile/Tail mode launch.
#
# Bug: pressing Tab launched Tile mode, which "started and immediately died"
# with no visible error. switch_to_tile created the tile window with
# `2>/dev/null || true` and then detached the Navigator unconditionally, so
# when the session server had no live session the new-window failed silently,
# the Navigator detached anyway, and the user was dropped out of Tile mode
# with nothing to explain why.

load 'test_helper'

setup() {
    # Isolate the tmux servers BEFORE common.sh freezes the socket names into
    # readonly vars, so these tests never touch the user's real servers.
    export TMUX_TMPDIR="/tmp/tw-test-$$"
    mkdir -p "$TMUX_TMPDIR"
    export CLAUDE_TOWER_SESSION_SOCKET="tst-sess-$$"
    export CLAUDE_TOWER_NAV_SOCKET="tst-nav-$$"

    source_common
    setup_test_env

    SCRIPT_DIR="${BATS_TEST_DIRNAME}/../tmux-plugin/scripts"
    # Pull in the launch helpers under test. source_common already loaded
    # common.sh, so tell navigator-list.sh to skip its own copy (its readonly
    # vars would collide) and to not start the render loop.
    TOWER_COMMON_LOADED=1 source "${SCRIPT_DIR}/navigator-list.sh"
}

teardown() {
    session_tmux kill-server 2>/dev/null || true
    nav_tmux kill-server 2>/dev/null || true
    rm -rf "$TMUX_TMPDIR"
    teardown_test_env
}

# ---------------------------------------------------------------------------
# tile_target_session: the guard that decides whether Tile mode can launch
# ---------------------------------------------------------------------------

@test "tile_target_session: fails when the session server has no session" {
    # No session server running at all -> nothing to attach to.
    run tile_target_session
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "tile_target_session: returns the session when one is live" {
    session_tmux new-session -d -s "tower_probe" "sleep 30"
    run tile_target_session
    [ "$status" -eq 0 ]
    [ "$output" = "tower_probe" ]
    session_tmux kill-session -t "tower_probe" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# launch_view_window: must report failure instead of swallowing it
# ---------------------------------------------------------------------------

@test "launch_view_window: fails when the session server is not running" {
    run launch_view_window "tower-tile" "${SCRIPT_DIR}/tile.sh"
    [ "$status" -ne 0 ]
}

@test "launch_view_window: succeeds and creates the window when server is up" {
    session_tmux new-session -d -s "tower_probe" "sleep 30"

    run launch_view_window "tower-tile" "sleep 30"
    [ "$status" -eq 0 ]

    run session_tmux list-windows -a -F '#{window_name}'
    [[ "$output" == *"tower-tile"* ]]

    session_tmux kill-session -t "tower_probe" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# switch_to_tile: must NOT detach the Navigator when the launch failed
# ---------------------------------------------------------------------------

@test "switch_to_tile: does not detach the Navigator when launch fails" {
    marker="${BATS_TEST_TMPDIR}/detached"
    # Stub the detach so a regression (detaching on a failed launch) is visible.
    nav_tmux() {
        if [[ "$1" == "detach-client" ]]; then
            echo "detached" >"$marker"
        fi
        return 0
    }

    # No session server -> launch must fail -> no detach.
    run switch_to_tile
    [ "$status" -ne 0 ]
    [ ! -f "$marker" ]
}

@test "switch_to_tile: surfaces an error message when it cannot launch" {
    run switch_to_tile
    [ "$status" -ne 0 ]
    # The user must be told something, not dropped out silently.
    [[ "$output" == *"No running session"* ]]
}

@test "switch_to_tail: also refuses to detach with no running session" {
    marker="${BATS_TEST_TMPDIR}/detached"
    nav_tmux() {
        if [[ "$1" == "detach-client" ]]; then
            echo "detached" >"$marker"
        fi
        return 0
    }

    run switch_to_tail
    [ "$status" -ne 0 ]
    [ ! -f "$marker" ]
    [[ "$output" == *"Tail"* ]]
}

# ---------------------------------------------------------------------------
# Tab must survive the key read
#
# `read -rsn1 key` uses the default IFS, which contains TAB -- so a pressed Tab
# was word-split away and arrived as the empty string, matching the `''`
# (Enter) branch instead of `$'\t'`. Tile mode was unreachable by its own
# documented key. Reading with `IFS=` keeps the byte intact.
# ---------------------------------------------------------------------------

@test "read -rsn1: default IFS swallows Tab (the bug)" {
    run bash -c 'printf "\t" | { read -rsn1 k; printf "%s" "${#k}"; }'
    [ "$output" = "0" ]
}

@test "read -rsn1: IFS= preserves Tab (the fix)" {
    run bash -c 'printf "\t" | { IFS= read -rsn1 k; printf "%s" "${#k}"; }'
    [ "$output" = "1" ]
}

@test "key dispatch: a piped Tab byte reaches the Tab branch, not Enter" {
    # Drive the real read-then-case shape used by the main loop. With the
    # bare `read -rsn1` this reports ENTER (the regression); with `IFS=` it
    # reports TAB.
    run bash -c '
        printf "\t" | {
            IFS= read -rsn1 -t 1 key
            case "$key" in
                $'"'"'\t'"'"') echo TAB ;;
                "")   echo ENTER ;;
                *)    echo OTHER ;;
            esac
        }'
    [ "$output" = "TAB" ]
}

@test "key dispatch: ordinary keys are unaffected by IFS=" {
    # IFS= applies to every key read, so verify a normal key still arrives.
    run bash -c '
        printf "t" | {
            IFS= read -rsn1 -t 1 key
            printf "%s" "$key"
        }'
    [ "$output" = "t" ]
}

# ---------------------------------------------------------------------------
# tile.sh itself must survive a draw with a small session count
# ---------------------------------------------------------------------------

@test "tile.sh: passes shellcheck" {
    command -v shellcheck >/dev/null || skip "shellcheck not installed"
    run shellcheck -e SC2034,SC1091,SC2317 "${SCRIPT_DIR}/tile.sh"
    [ "$status" -eq 0 ]
}
