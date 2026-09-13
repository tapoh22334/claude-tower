#!/usr/bin/env bats
# test_nav_state_ownership.bats
#
# The Navigator's cursor lives in a shared state file, read back by the `D`
# handler to decide what to delete. `q` only detaches the client, and the
# pane-exited hook respawns navigator-list.sh, so a list loop can outlive the
# Navigator that owned it and keep writing its own cursor into that file.
#
# When that happened the visible Navigator drew its highlight from its own
# in-memory array while the stale loop owned the file, so the confirmation
# prompt named the row under the cursor and session-delete.sh was handed a
# different id. A session the user never selected was deleted, irreversibly.
#
# These tests pin the writer-side guard: only the pane that currently owns
# the state may write it.

load 'test_helper'

setup() {
    # Point the state dir at the test's own scratch space. This is what the
    # overridable TOWER_NAV_STATE_DIR buys: before it, these tests could only
    # have run against the real /tmp/claude-tower.
    export CLAUDE_TOWER_NAV_STATE_DIR="${BATS_TEST_TMPDIR}/nav-state"
    source_common
    setup_test_env
    ensure_nav_state_dir
}

teardown() {
    teardown_test_env
}

@test "nav state dir: honours CLAUDE_TOWER_NAV_STATE_DIR" {
    [[ "$TOWER_NAV_STATE_DIR" == "${BATS_TEST_TMPDIR}/nav-state" ]]
}

@test "nav state dir: defaults to /tmp/claude-tower when unset" {
    run bash -c "unset CLAUDE_TOWER_NAV_STATE_DIR; source '$PROJECT_ROOT/tmux-plugin/lib/common.sh' 2>/dev/null; echo \"\$TOWER_NAV_STATE_DIR\""
    [[ "$output" == "/tmp/claude-tower" ]]
}

@test "ownership: a caller with no pane writes freely" {
    unset TOWER_NAV_PANE
    set_nav_selected "tower_aaaaaaaa-0000-0000-0000-000000000000"
    [[ "$(get_nav_selected)" == "tower_aaaaaaaa-0000-0000-0000-000000000000" ]]
}

@test "ownership: the first list pane to write claims the state" {
    export TOWER_NAV_PANE="%1"
    set_nav_selected "tower_aaaaaaaa-0000-0000-0000-000000000000"
    [[ "$(get_nav_selected)" == "tower_aaaaaaaa-0000-0000-0000-000000000000" ]]
    [[ "$(cat "$TOWER_NAV_OWNER_FILE")" == "%1" ]]
}

@test "ownership: the owning pane keeps writing" {
    export TOWER_NAV_PANE="%1"
    claim_nav_state
    set_nav_selected "tower_bbbbbbbb-0000-0000-0000-000000000000"
    [[ "$(get_nav_selected)" == "tower_bbbbbbbb-0000-0000-0000-000000000000" ]]
}

# The regression itself: the stale loop must not be able to move the cursor
# out from under the live Navigator.
@test "ownership: a stale pane cannot overwrite the live cursor" {
    export TOWER_NAV_PANE="%2"
    # Claim via a plain write, so this test states the requirement in terms
    # of set_nav_selected alone and fails on the unguarded code by asserting
    # the wrong id rather than by tripping over a missing helper.
    set_nav_selected "tower_cccccccc-0000-0000-0000-000000000000"

    # The loop left over from a previous Navigator tries to write its own.
    export TOWER_NAV_PANE="%1"
    set_nav_selected "tower_dddddddd-0000-0000-0000-000000000000"

    [[ "$(get_nav_selected)" == "tower_cccccccc-0000-0000-0000-000000000000" ]]
}

@test "ownership: a stale pane's write is silent, not an error" {
    export TOWER_NAV_PANE="%2"
    claim_nav_state
    export TOWER_NAV_PANE="%1"
    run set_nav_selected "tower_dddddddd-0000-0000-0000-000000000000"
    [ "$status" -eq 0 ]
}

# A respawned pane keeps the same pane id, which is why ownership is recorded
# per pane and not per PID: auto-restart must not look like a stale writer.
@test "ownership: a respawned pane keeps its claim" {
    export TOWER_NAV_PANE="%1"
    claim_nav_state
    set_nav_selected "tower_eeeeeeee-0000-0000-0000-000000000000"

    # Same pane, new process after respawn-pane.
    run bash -c "
        export CLAUDE_TOWER_NAV_STATE_DIR='$TOWER_NAV_STATE_DIR'
        export TOWER_NAV_PANE='%1'
        source '$PROJECT_ROOT/tmux-plugin/lib/common.sh' 2>/dev/null
        set_nav_selected 'tower_ffffffff-0000-0000-0000-000000000000'
        get_nav_selected
    "
    [[ "$output" == "tower_ffffffff-0000-0000-0000-000000000000" ]]
}

@test "ownership: a new Navigator takes the claim from the old one" {
    export TOWER_NAV_PANE="%1"
    claim_nav_state
    set_nav_selected "tower_11111111-0000-0000-0000-000000000000"

    # The user opens a fresh Navigator; its list pane claims on startup.
    export TOWER_NAV_PANE="%2"
    claim_nav_state
    set_nav_selected "tower_22222222-0000-0000-0000-000000000000"
    [[ "$(get_nav_selected)" == "tower_22222222-0000-0000-0000-000000000000" ]]

    # And the pane it displaced can no longer move the cursor.
    export TOWER_NAV_PANE="%1"
    set_nav_selected "tower_11111111-0000-0000-0000-000000000000"
    [[ "$(get_nav_selected)" == "tower_22222222-0000-0000-0000-000000000000" ]]
}

@test "ownership: focus is gated the same way as the cursor" {
    export TOWER_NAV_PANE="%2"
    set_nav_focus "view"
    export TOWER_NAV_PANE="%1"
    set_nav_focus "list"
    [[ "$(get_nav_focus)" == "view" ]]
}

# set_nav_caller stays ungated on purpose: open_navigator records the caller
# from the user's own shell, outside any Navigator pane, before the list pane
# exists to claim ownership. Gating it would drop the return target.
@test "ownership: the caller is still recorded from outside a pane" {
    export TOWER_NAV_PANE="%2"
    claim_nav_state
    unset TOWER_NAV_PANE
    set_nav_caller "tower_99999999-0000-0000-0000-000000000000"
    [[ "$(get_nav_caller)" == "tower_99999999-0000-0000-0000-000000000000" ]]
}

@test "ownership: cleanup clears the owner along with the state" {
    export TOWER_NAV_PANE="%1"
    claim_nav_state
    set_nav_selected "tower_11111111-0000-0000-0000-000000000000"
    cleanup_nav_state
    [[ ! -f "$TOWER_NAV_OWNER_FILE" ]]
    [[ ! -f "$TOWER_NAV_SELECTED_FILE" ]]
}

# What the user actually experienced: the prompt named one session and a
# different one died. The id the D handler reads must be the one on screen.
@test "delete targets the session the live Navigator has selected" {
    export TOWER_NAV_PANE="%2"
    set_nav_selected "tower_1deab190-540f-4830-bf57-43036bc8fcce"

    # Stale loop from the previous Navigator, still ticking.
    export TOWER_NAV_PANE="%1"
    set_nav_selected "tower_2df789a3-63d6-478c-a352-63fe87b86711"

    # `D` reads the file; it must see the live selection.
    export TOWER_NAV_PANE="%2"
    local doomed
    doomed=$(get_nav_selected)
    [[ "$doomed" == "tower_1deab190-540f-4830-bf57-43036bc8fcce" ]]
}
