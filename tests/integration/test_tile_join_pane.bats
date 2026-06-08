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
