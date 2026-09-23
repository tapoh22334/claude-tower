#!/usr/bin/env bats
# Tile view on a real tmux server (#31).
#
# Tile broke twice without a unit test noticing: once it drew one frame and
# exited (a `[[ … ]] && break` under set -e), once it opened in a session the
# user was not attached to. Its unit tests call functions one at a time; the
# failures were in how the script runs inside a pane. So run it inside one —
# a tower-tile window on a throwaway session server, exactly as
# _switch_to_view launches it — and look at the screen.

load '../test_helper'

NAV_SOCKET="ct-tilelive-nav"
SESSION_SOCKET="ct-tilelive-session"

setup_file() {
    export TMUX_TMPDIR="/tmp/claude-tower-tilelive-test"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"
}

teardown_file() {
    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    rm -rf "$TMUX_TMPDIR" 2>/dev/null || true
}

setup() {
    export CLAUDE_TOWER_SESSION_SOCKET="$SESSION_SOCKET"
    export CLAUDE_TOWER_NAV_SOCKET="$NAV_SOCKET"
    setup_test_env
    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    # A Navigator session to hand back to (no client attached: the handoff
    # then finds no outer client and simply lets the window close).
    TMUX= tmux -L "$NAV_SOCKET" new-session -d -s navigator -x 160 -y 40 "sleep 120"
}

teardown() {
    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    teardown_test_env
}

_make_sessions() {
    local n="$1" i
    for ((i = 1; i <= n; i++)); do
        TMUX= tmux -L "$SESSION_SOCKET" new-session -d -x 150 -y 40 \
            -s "tower_$(printf '%08d' "$i")-0000-4000-8000-000000000000" -c /tmp "sleep 120"
    done
}

_first() { echo "tower_00000001-0000-4000-8000-000000000000"; }

# Launch tile.sh the way _switch_to_view does: a window in the first tower
# session, carrying this test's sockets and state dir.
_launch_tile() {
    TMUX= tmux -L "$SESSION_SOCKET" new-window -d -t "$(_first)" -n tower-tile \
        -e "CLAUDE_TOWER_NAV_SOCKET=$NAV_SOCKET" \
        -e "CLAUDE_TOWER_SESSION_SOCKET=$SESSION_SOCKET" \
        -e "CLAUDE_TOWER_NAV_STATE_DIR=$CLAUDE_TOWER_NAV_STATE_DIR" \
        -e "CLAUDE_TOWER_METADATA_DIR=$CLAUDE_TOWER_METADATA_DIR" \
        -e "CLAUDE_PROJECTS_DIR=$CLAUDE_PROJECTS_DIR" \
        -e "TMUX_TMPDIR=$TMUX_TMPDIR" \
        "$PROJECT_ROOT/tmux-plugin/scripts/tile.sh"
    local i
    for ((i = 0; i < 50; i++)); do
        _tile_screen | grep -q "Tile View" && return 0
        sleep 0.1
    done
    return 1
}

_tile_screen() {
    TMUX= tmux -L "$SESSION_SOCKET" capture-pane -t "$(_first):tower-tile" -p 2>/dev/null
}

_tile_window_exists() {
    TMUX= tmux -L "$SESSION_SOCKET" list-windows -t "$(_first)" -F '#{window_name}' 2>/dev/null | grep -qx tower-tile
}

_tile_key() {
    TMUX= tmux -L "$SESSION_SOCKET" send-keys -t "$(_first):tower-tile" "$@"
}

@test "tile: draws the grid inside a real pane and stays up (no one-frame exit)" {
    _make_sessions 3
    _launch_tile
    sleep 1.5
    _tile_window_exists
    run _tile_screen
    [[ "$output" == *"Tile View"* ]]
    [[ "$output" == *"[1]"* ]]
    [[ "$output" == *"[2]"* ]]
    [[ "$output" == *"[3]"* ]]
}

@test "tile: more sessions than fit are capped, without an error or a crash" {
    _make_sessions 8
    _launch_tile
    sleep 1
    run _tile_screen
    [[ "$output" == *"[6]"* ]]
    [[ "$output" != *"[7]"* ]]
    [[ "$output" != *"too small"* ]]
    [[ "$output" != *"error"* ]]
    _tile_window_exists
}

@test "tile: Enter closes the window and keeps the list's selection" {
    _make_sessions 3
    local second="tower_00000002-0000-4000-8000-000000000000"
    echo "$second" >"$CLAUDE_TOWER_NAV_STATE_DIR/selected"
    _launch_tile
    _tile_key Enter
    local i
    for ((i = 0; i < 30; i++)); do
        _tile_window_exists || break
        sleep 0.1
    done
    ! _tile_window_exists
    [ "$(cat "$CLAUDE_TOWER_NAV_STATE_DIR/selected")" = "$second" ]
}

@test "tile: j then Enter hands the next session's id back to the list" {
    _make_sessions 3
    echo "$(_first)" >"$CLAUDE_TOWER_NAV_STATE_DIR/selected"
    _launch_tile
    _tile_key j
    sleep 0.3
    _tile_key Enter
    local i
    for ((i = 0; i < 30; i++)); do
        _tile_window_exists || break
        sleep 0.1
    done
    [ "$(cat "$CLAUDE_TOWER_NAV_STATE_DIR/selected")" = "tower_00000002-0000-4000-8000-000000000000" ]
}

# Tail shares the launch shape and the exit path; pin the same two things.
_launch_tail() {
    TMUX= tmux -L "$SESSION_SOCKET" new-window -d -t "$(_first)" -n tower-tail \
        -e "CLAUDE_TOWER_NAV_SOCKET=$NAV_SOCKET" \
        -e "CLAUDE_TOWER_SESSION_SOCKET=$SESSION_SOCKET" \
        -e "CLAUDE_TOWER_NAV_STATE_DIR=$CLAUDE_TOWER_NAV_STATE_DIR" \
        -e "CLAUDE_TOWER_METADATA_DIR=$CLAUDE_TOWER_METADATA_DIR" \
        -e "CLAUDE_PROJECTS_DIR=$CLAUDE_PROJECTS_DIR" \
        -e "TMUX_TMPDIR=$TMUX_TMPDIR" \
        "$PROJECT_ROOT/tmux-plugin/scripts/tail-view.sh"
    local i
    for ((i = 0; i < 50; i++)); do
        TMUX= tmux -L "$SESSION_SOCKET" capture-pane -t "$(_first):tower-tail" -p 2>/dev/null | grep -q "Tail" && return 0
        sleep 0.1
    done
    return 1
}

@test "tail: draws inside a real pane and Enter keeps the list's selection" {
    _make_sessions 3
    local second="tower_00000002-0000-4000-8000-000000000000"
    echo "$second" >"$CLAUDE_TOWER_NAV_STATE_DIR/selected"
    _launch_tail
    TMUX= tmux -L "$SESSION_SOCKET" send-keys -t "$(_first):tower-tail" Enter
    local i
    for ((i = 0; i < 30; i++)); do
        TMUX= tmux -L "$SESSION_SOCKET" list-windows -t "$(_first)" -F '#{window_name}' | grep -qx tower-tail || break
        sleep 0.1
    done
    ! TMUX= tmux -L "$SESSION_SOCKET" list-windows -t "$(_first)" -F '#{window_name}' | grep -qx tower-tail
    [ "$(cat "$CLAUDE_TOWER_NAV_STATE_DIR/selected")" = "$second" ]
}
