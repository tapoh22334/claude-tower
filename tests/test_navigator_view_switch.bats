#!/usr/bin/env bats
# test_navigator_view_switch.bats
#
# signal_view_update must pick the right tmux verb for the selected session:
#   - live session on the session server -> switch-client (retarget in place)
#   - not-live (dormant / unregistered)  -> detach-client (drop the stale pane
#     so navigator-view.sh's poll loop can paint the dormant/placeholder screen)
#
# The old code always ran switch-client; for a dormant target that fails and
# leaves the previous session's pane on screen. These tests pin the branch.

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    rm -f "$TOWER_NAV_SELECTED_FILE" 2>/dev/null || true
    teardown_test_env
}

# Source navigator-list.sh's function bodies without running main_loop
# (guarded by BASH_SOURCE[0] == $0). set +euo survives the re-source of
# common.sh (readonly re-declarations) exactly as the other nav tests do.
source_navigator_list_functions() {
    set +euo pipefail
    # shellcheck disable=SC1090
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true
    set -euo pipefail
}

# Install tmux-wrapper stubs that record the chosen verb into CALLS_FILE and
# let LIVE_SESSION decide whether has-session succeeds.
_install_stubs() {
    CALLS_FILE="$BATS_TEST_TMPDIR/calls"
    : >"$CALLS_FILE"
    nav_tmux() {
        if [[ "$1" == "display-message" ]]; then
            echo "/dev/pts/fake"
            return 0
        fi
        echo "nav_tmux $*" >>"$CALLS_FILE"
    }
    session_tmux() {
        case "$1" in
            has-session)
                local sel="${@: -1}"
                [[ "$sel" == "${LIVE_SESSION:-}" ]]
                ;;
            *)
                echo "session_tmux $1" >>"$CALLS_FILE"
                ;;
        esac
    }
}

@test "signal_view_update: live selection uses switch-client, not detach-client" {
    source_navigator_list_functions
    _install_stubs
    LIVE_SESSION="tower_deadbeef-0000-0000-0000-000000000000"
    set_nav_selected "$LIVE_SESSION"
    signal_view_update
    grep -q "session_tmux switch-client" "$CALLS_FILE"
    ! grep -q "session_tmux detach-client" "$CALLS_FILE"
}

@test "signal_view_update: dormant selection uses detach-client, not switch-client" {
    source_navigator_list_functions
    _install_stubs
    LIVE_SESSION="__none__"
    set_nav_selected "tower_deadbeef-0000-0000-0000-000000000000"
    signal_view_update
    grep -q "session_tmux detach-client" "$CALLS_FILE"
    ! grep -q "session_tmux switch-client" "$CALLS_FILE"
}

@test "signal_view_update: empty selection does nothing" {
    source_navigator_list_functions
    _install_stubs
    LIVE_SESSION="__none__"
    set_nav_selected ""
    signal_view_update
    [ ! -s "$CALLS_FILE" ]
}
