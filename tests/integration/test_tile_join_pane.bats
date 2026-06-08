#!/usr/bin/env bats
# Behavioural tests for the join-pane Tile View (lib/tile.sh).
# Each Claude session is stood in by `/bin/sleep 600` so panes have a
# stable PID we can track across the collapse/disband round trip.

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SESSION_SOCKET="ct-tile-sess-$$"

setup() {
    export TMUX_TMPDIR="/tmp/ct-tile-$$"
    mkdir -p "$TMUX_TMPDIR"; chmod 700 "$TMUX_TMPDIR"
    export CLAUDE_TOWER_SESSION_SOCKET="$SESSION_SOCKET"
    export TOWER_NAV_STATE_DIR_OVERRIDE="/tmp/ct-tile-state-$$"
    rm -rf "$TOWER_NAV_STATE_DIR_OVERRIDE"; mkdir -p "$TOWER_NAV_STATE_DIR_OVERRIDE"

    # common.sh sets strict mode + an ERR trap that, under bats, can spiral
    # on a failing assertion. Source defensively and drop the trap — this
    # mirrors tests/integration/test_return_to_caller.bats.
    set +euo pipefail
    # shellcheck disable=SC1090,SC1091
    source "$PROJECT_ROOT/tmux-plugin/lib/common.sh"
    source "$PROJECT_ROOT/tmux-plugin/lib/tile.sh"
    set -euo pipefail
    trap - ERR

    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
}

teardown() {
    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
    rm -rf "$TMUX_TMPDIR" "$TOWER_NAV_STATE_DIR_OVERRIDE" 2>/dev/null || true
}

# Make an active Claude session: one window named `claude` running sleep.
make_claude() {
    local name="$1"
    TMUX= tmux -L "$SESSION_SOCKET" new-session -d -s "tower_${name}" \
        -n claude -x 200 -y 50 "exec /bin/sleep 600"
}

@test "tile: constants are defined" {
    [ "$TOWER_TILE_SESSION" = "tower-tile" ]
    [ "$TOWER_TILE_HOLDER_WINDOW" = "_tile_holder" ]
    [ -n "$TOWER_TILE_MAP_FILE" ]
}

# Hand-build a tile state: collapse one claude pane into tower-tile with a
# holder left behind, write the map, then disband and assert restoration.
@test "tile_disband: restores session by name with same PID" {
    make_claude alpha
    local pid; pid=$(TMUX= tmux -L "$SESSION_SOCKET" \
        list-panes -t tower_alpha:claude -F '#{pane_pid}')
    local pane; pane=$(TMUX= tmux -L "$SESSION_SOCKET" \
        list-panes -t tower_alpha:claude -F '#{pane_id}')

    # Build tile-tile session + holder, then join the claude pane in.
    TMUX= tmux -L "$SESSION_SOCKET" new-session -d -s tower-tile -n tile "exec /bin/sleep 600"
    local tw; tw=$(TMUX= tmux -L "$SESSION_SOCKET" display-message -p -t tower-tile '#{window_id}')
    TMUX= tmux -L "$SESSION_SOCKET" new-window -d -t tower_alpha -n _tile_holder "exec /bin/sleep 600"
    TMUX= tmux -L "$SESSION_SOCKET" set-option -p -t "$pane" @tower_name tower_alpha
    printf '%s\t%s\n' "$pane" tower_alpha >"$TOWER_TILE_MAP_FILE"
    TMUX= tmux -L "$SESSION_SOCKET" join-pane -s "$pane" -t "$tw"

    run tile_disband
    [ "$status" -eq 0 ]

    # tower_alpha restored, single window named claude, same PID, no holder.
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_alpha
    local wc; wc=$(TMUX= tmux -L "$SESSION_SOCKET" list-windows -t tower_alpha | wc -l)
    [ "$wc" -eq 1 ]
    local newpid; newpid=$(TMUX= tmux -L "$SESSION_SOCKET" \
        list-panes -t tower_alpha -F '#{pane_pid}')
    [ "$newpid" = "$pid" ]
    ! TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower-tile
    [ ! -f "$TOWER_TILE_MAP_FILE" ]
}

@test "tile_disband: skips a crashed pane and warns (non-zero)" {
    make_claude beta
    local pane; pane=$(TMUX= tmux -L "$SESSION_SOCKET" \
        list-panes -t tower_beta:claude -F '#{pane_id}')
    # Map references a pane id that does not exist (simulated crash).
    printf '%s\t%s\n' "%999" tower_beta >"$TOWER_TILE_MAP_FILE"

    run tile_disband
    [ "$status" -eq 1 ]                 # anomaly reported
    [ ! -f "$TOWER_TILE_MAP_FILE" ]     # map still cleared
}

@test "tile_disband: no map file is a clean no-op" {
    run tile_disband
    [ "$status" -eq 0 ]
}

@test "tile_collapse: collapses N sessions into tower-tile, panes tagged" {
    make_claude one; make_claude two; make_claude three
    run tile_collapse
    [ "$status" -eq 0 ]

    # tower-tile exists with one pane per session.
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower-tile
    local pc; pc=$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower-tile | wc -l)
    [ "$pc" -eq 3 ]

    # Each pane carries @tower_name; map file matches.
    local tags; tags=$(TMUX= tmux -L "$SESSION_SOCKET" \
        list-panes -t tower-tile -F '#{@tower_name}' | sort | tr '\n' ' ')
    [ "$tags" = "tower_one tower_three tower_two " ]
    [ "$(wc -l <"$TOWER_TILE_MAP_FILE")" -eq 3 ]

    # Each source session is still alive (held by _tile_holder).
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_one
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_two
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_three
}

@test "tile_collapse: round-trips back to standalone sessions, same PIDs" {
    make_claude a; make_claude b
    local pa; pa=$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower_a:claude -F '#{pane_pid}')
    local pb; pb=$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower_b:claude -F '#{pane_pid}')

    tile_collapse
    tile_disband

    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_a
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_b
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower_a -F '#{pane_pid}')" = "$pa" ]
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower_b -F '#{pane_pid}')" = "$pb" ]
    ! TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower-tile
}

@test "tile_collapse: 5 sessions tile without 'pane too small'" {
    make_claude s1; make_claude s2; make_claude s3; make_claude s4; make_claude s5
    run tile_collapse
    [ "$status" -eq 0 ]
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower-tile | wc -l)" -eq 5 ]
}

@test "tile_collapse: multi-window session is skipped and counted" {
    make_claude solo
    make_claude multi
    TMUX= tmux -L "$SESSION_SOCKET" new-window -d -t tower_multi -n extra "exec /bin/sleep 600"

    tile_collapse
    # Only the single-window session is tiled.
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower-tile | wc -l)" -eq 1 ]
    # The skip count is exposed via the global TILE_SKIPPED.
    [ "$TILE_SKIPPED" -eq 1 ]
    # The multi-window session is untouched.
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-windows -t tower_multi | wc -l)" -eq 2 ]
}

@test "tile_collapse: no tileable sessions returns non-zero, builds nothing" {
    run tile_collapse
    [ "$status" -ne 0 ]
    ! TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower-tile
}

@test "tile_collapse: re-entry after interrupted state recovers (idempotent)" {
    make_claude x; make_claude y
    tile_collapse
    # Simulate a fresh ENTER while already tiled: should disband then rebuild.
    run tile_collapse
    [ "$status" -eq 0 ]
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower-tile | wc -l)" -eq 2 ]
    # No stray holders left in the sessions.
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-windows -t tower_x | wc -l)" -eq 1 ]
}

@test "tile-exit.sh: disbands tile and restores sessions" {
    make_claude p; make_claude q
    tile_collapse
    # TOWER_TILE_NO_REENTER short-circuits the navigator exec for tests.
    TOWER_TILE_NO_REENTER=1 run "$PROJECT_ROOT/tmux-plugin/scripts/tile-exit.sh"
    [ "$status" -eq 0 ]
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_p
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_q
    ! TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower-tile
}

@test "tile-exit.sh: writes a warning on teardown anomaly" {
    make_claude r
    tile_collapse
    # Corrupt the map so one entry references a dead pane.
    printf '%s\t%s\n' "%999" tower_ghost >>"$TOWER_TILE_MAP_FILE"
    TOWER_TILE_NO_REENTER=1 run "$PROJECT_ROOT/tmux-plugin/scripts/tile-exit.sh"
    # Warning file exists for the Navigator to surface.
    [ -f "$TOWER_NAV_WARNING_FILE" ]
}
