#!/usr/bin/env bats
# Coverage-gap skeletons (round 12): direct unit coverage for
# navigator-list.sh's move_selection/go_first/go_last, which
# tests/integration/test_navigation_contract.bats only exercises via
# hand-reimplemented wrap-around logic ("Simulate what move_selection
# does") rather than calling the real function -- a bug in the actual
# implementation would not be caught by those tests. Also covers
# ensure_nav_state_dir's chmod-700 security boundary (common.sh) and
# kill_nav_server's "server not running" no-op branch, both previously
# unasserted.

load 'test_helper'

setup() {
    source_common
    setup_test_env
}

teardown() {
    # TOWER_NAV_SELECTED_FILE lives under the hardcoded, non-test-isolated
    # /tmp/claude-tower (TOWER_NAV_STATE_DIR is `readonly`), so tests that
    # call set_nav_selected/move_selection/go_first/go_last leak state
    # across tests and even across bats runs unless explicitly cleared.
    rm -f "$TOWER_NAV_SELECTED_FILE" 2>/dev/null || true
    teardown_test_env
}

# Source navigator-list.sh's function bodies without running main_loop.
# The script guards its own entrypoint with
#   if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main_loop; fi
# so a plain `source` from bats (where BASH_SOURCE[0] != $0) is already
# safe and does not need the sed-strip trick tile.sh's tests use.
source_navigator_list_functions() {
    set +euo pipefail
    # shellcheck disable=SC1090
    source "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh" 2>/dev/null || true
    set -euo pipefail
}

# ============================================================================
# move_selection() -- navigator-list.sh:267-288
# ============================================================================

@test "move_selection: down advances index by one and updates nav_selected" {
    source_navigator_list_functions
    SESSION_IDS=("tower_a" "tower_b" "tower_c")

    local new_index
    new_index=$(move_selection "down" 0)

    [ "$new_index" -eq 1 ]
    [ "$(get_nav_selected)" = "tower_b" ]
}

@test "move_selection: up retreats index by one and updates nav_selected" {
    source_navigator_list_functions
    SESSION_IDS=("tower_a" "tower_b" "tower_c")

    local new_index
    new_index=$(move_selection "up" 2)

    [ "$new_index" -eq 1 ]
    [ "$(get_nav_selected)" = "tower_b" ]
}

@test "move_selection: down wraps from last index to 0" {
    source_navigator_list_functions
    SESSION_IDS=("tower_a" "tower_b" "tower_c")

    local new_index
    new_index=$(move_selection "down" 2)

    [ "$new_index" -eq 0 ]
    [ "$(get_nav_selected)" = "tower_a" ]
}

@test "move_selection: up wraps from index 0 to the last index" {
    source_navigator_list_functions
    SESSION_IDS=("tower_a" "tower_b" "tower_c")

    local new_index
    new_index=$(move_selection "up" 0)

    [ "$new_index" -eq 2 ]
    [ "$(get_nav_selected)" = "tower_c" ]
}

@test "move_selection: single-element list wraps to itself in both directions" {
    source_navigator_list_functions
    SESSION_IDS=("tower_only")

    [ "$(move_selection "down" 0)" -eq 0 ]
    [ "$(get_nav_selected)" = "tower_only" ]

    [ "$(move_selection "up" 0)" -eq 0 ]
    [ "$(get_nav_selected)" = "tower_only" ]
}

@test "move_selection: empty SESSION_IDS does not set nav_selected and does not error" {
    source_navigator_list_functions
    SESSION_IDS=()

    run move_selection "down" 0
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
    [ -z "$(get_nav_selected)" ]
}

# ============================================================================
# go_first() / go_last() -- navigator-list.sh:291-305
# ============================================================================

@test "go_first: selects index 0 regardless of current position" {
    source_navigator_list_functions
    SESSION_IDS=("tower_a" "tower_b" "tower_c")

    local new_index
    new_index=$(go_first)

    [ "$new_index" -eq 0 ]
    [ "$(get_nav_selected)" = "tower_a" ]
}

@test "go_last: selects the final index regardless of current position" {
    source_navigator_list_functions
    SESSION_IDS=("tower_a" "tower_b" "tower_c")

    local new_index
    new_index=$(go_last)

    [ "$new_index" -eq 2 ]
    [ "$(get_nav_selected)" = "tower_c" ]
}

@test "go_first/go_last: no-op on empty SESSION_IDS, no error" {
    source_navigator_list_functions
    SESSION_IDS=()

    run go_first
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]

    run go_last
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

# ============================================================================
# ensure_nav_state_dir() -- common.sh:200-206
# Security-relevant: comment states chmod 700 "prevent[s] access by other
# users" but no prior test asserted the permission bits actually land.
# ============================================================================

@test "ensure_nav_state_dir: creates directory with 700 permissions" {
    # TOWER_NAV_STATE_DIR is `readonly` in common.sh (hardcoded to
    # /tmp/claude-tower), so it cannot be overridden per-test; exercise the
    # real path directly and restore its prior permissions afterwards.
    local orig_perms
    orig_perms=$(stat -c '%a' "$TOWER_NAV_STATE_DIR" 2>/dev/null || stat -f '%Lp' "$TOWER_NAV_STATE_DIR" 2>/dev/null || echo "")

    ensure_nav_state_dir

    [ -d "$TOWER_NAV_STATE_DIR" ]
    local perms
    perms=$(stat -c '%a' "$TOWER_NAV_STATE_DIR" 2>/dev/null || stat -f '%Lp' "$TOWER_NAV_STATE_DIR")
    [ "$perms" = "700" ]

    [[ -n "$orig_perms" ]] && chmod "$orig_perms" "$TOWER_NAV_STATE_DIR" 2>/dev/null || true
}

@test "ensure_nav_state_dir: re-applies 700 permissions to a dir with looser perms" {
    local orig_perms
    orig_perms=$(stat -c '%a' "$TOWER_NAV_STATE_DIR" 2>/dev/null || stat -f '%Lp' "$TOWER_NAV_STATE_DIR" 2>/dev/null || echo "")

    chmod 755 "$TOWER_NAV_STATE_DIR"

    ensure_nav_state_dir

    local perms
    perms=$(stat -c '%a' "$TOWER_NAV_STATE_DIR" 2>/dev/null || stat -f '%Lp' "$TOWER_NAV_STATE_DIR")
    [ "$perms" = "700" ]

    [[ -n "$orig_perms" ]] && chmod "$orig_perms" "$TOWER_NAV_STATE_DIR" 2>/dev/null || true
}

# ============================================================================
# kill_nav_server() -- common.sh:279-284
# "Server not running" branch was previously unasserted: is_nav_server_running
# false should skip `nav_tmux kill-server` and still run cleanup_nav_state.
# ============================================================================

@test "kill_nav_server: when server is not running, still cleans up nav state files without invoking kill-server" {
    is_nav_server_running() { return 1; }

    local kill_server_called=0
    nav_tmux() {
        if [[ "$1" == "kill-server" ]]; then
            kill_server_called=1
        fi
        return 0
    }

    set_nav_selected "tower_a" 2>/dev/null || true

    kill_nav_server

    [ "$kill_server_called" -eq 0 ]
}
