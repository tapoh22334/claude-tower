#!/usr/bin/env bats
# A Navigator pane whose loop died must come back by itself (#63).
#
# The list loop used to be typed into a shell, so when it died the shell
# stayed and the pane never counted as dead: no hook fired and the person
# was left at a zsh prompt. Now the loop is the pane's command, the window
# has remain-on-exit, and the pane-died hook respawns the same pane with the
# same command. These run the real mechanism on a private tmux server.

load '../test_helper'

NAV_SOCKET="ct-respawn-nav"

setup_file() {
    export TMUX_TMPDIR="/tmp/claude-tower-respawn-test"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"
}

teardown_file() {
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    rm -rf "$TMUX_TMPDIR" 2>/dev/null || true
}

setup() {
    export CLAUDE_TOWER_NAV_SOCKET="$NAV_SOCKET"
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    source_common
    source "$PROJECT_ROOT/tmux-plugin/lib/error-recovery.sh"
    RUNLOG="$BATS_TEST_TMPDIR/runs.log"
    : >"$RUNLOG"
}

teardown() {
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
}

# _wait_for SECONDS CMD... — poll CMD every 0.1s until it succeeds.
_wait_for() {
    local n=$(($1 * 10))
    shift
    while ((n-- > 0)); do
        "$@" && return 0
        sleep 0.1
    done
    return 1
}

_count() { [ "$(grep -c "$1" "$RUNLOG")" -ge "$2" ]; }

@test "respawn: a list pane whose loop exits is re-run in the same pane with the same command" {
    TMUX= nav_tmux new-session -d -s "$TOWER_NAV_SESSION" -x 120 -y 30 \
        "echo list >>'$RUNLOG' 2>>'$BATS_TEST_TMPDIR/list.stderr.log'; sleep 0.3; exit 1"
    setup_pane_auto_restart
    nav_tmux split-window -t "$TOWER_NAV_SESSION" -h -l 70% "sleep 60"
    local pane
    pane=$(nav_tmux display -p -t "$TOWER_NAV_SESSION:0.0" '#{pane_id}')

    _wait_for 5 _count list 2

    # Same pane, both panes still there, and the command it was created with
    # (stderr log included) is what runs again.
    [ "$(nav_tmux display -p -t "$TOWER_NAV_SESSION:0.0" '#{pane_id}')" = "$pane" ]
    [ "$(nav_tmux list-panes -t "$TOWER_NAV_SESSION" | wc -l)" -eq 2 ]
    [[ "$(nav_tmux display -p -t "$pane" '#{pane_start_command}')" == *"list.stderr.log"* ]]
}

@test "respawn: killing the view pane's process brings the view back in the same pane" {
    TMUX= nav_tmux new-session -d -s "$TOWER_NAV_SESSION" -x 120 -y 30 "sleep 60"
    setup_pane_auto_restart
    nav_tmux split-window -t "$TOWER_NAV_SESSION" -h -l 70% "echo view >>'$RUNLOG'; sleep 60"
    _wait_for 3 _count view 1
    local pane pid
    pane=$(nav_tmux display -p -t "$TOWER_NAV_SESSION:0.1" '#{pane_id}')
    pid=$(nav_tmux display -p -t "$pane" '#{pane_pid}')

    kill "$pid"

    _wait_for 5 _count view 2
    _wait_for 2 bash -c "[ \"\$(TMUX= tmux -L '$NAV_SOCKET' display -p -t '$pane' '#{pane_dead}')\" = 0 ]"
    [ "$(nav_tmux display -p -t "$pane" '#{pane_pid}')" != "$pid" ]
    [ "$(nav_tmux list-panes -t "$TOWER_NAV_SESSION" | wc -l)" -eq 2 ]
}
