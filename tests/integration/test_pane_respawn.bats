#!/usr/bin/env bats
# A Navigator pane whose loop died must come back by itself (#63).
#
# The list loop used to be typed into a shell, so when it died the shell
# stayed and the pane never counted as dead: no hook fired and the person
# was left at a zsh prompt. Now the loop is the pane's command, the window
# has remain-on-exit, and the pane-died hook respawns the same pane with the
# same command. These run the real mechanism on a private tmux server.

load '../test_helper'

# Per bats run, like everything else test_helper namespaces: two runs at
# once must not kill each other's server. Kept short and under /tmp because
# a unix socket path has a length limit.
NAV_SOCKET="$CLAUDE_TOWER_NAV_SOCKET"

setup_file() {
    export TMUX_TMPDIR="/tmp/ct-respawn-${CLAUDE_TOWER_TEST_RUN_ID##*/}"
    mkdir -p "$TMUX_TMPDIR"
    chmod 700 "$TMUX_TMPDIR"
}

teardown_file() {
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    rm -rf "$TMUX_TMPDIR" 2>/dev/null || true
}

setup() {
    TMUX= tmux -L "$NAV_SOCKET" kill-server 2>/dev/null || true
    source_common
    source "$PROJECT_ROOT/tmux-plugin/lib/error-recovery.sh"
    # The hook runs nav-respawn.sh from this checkout.
    SCRIPT_DIR="$PROJECT_ROOT/tmux-plugin/scripts"
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

@test "respawn: a loop that dies every time is given up on after RESPAWN_MAX tries" {
    TMUX= nav_tmux new-session -d -s "$TOWER_NAV_SESSION" -x 120 -y 30 "sleep 60"
    setup_pane_auto_restart
    nav_tmux split-window -t "$TOWER_NAV_SESSION" -h -b -l 30% "echo crash >>'$RUNLOG'; exit 1"
    local pane
    pane=$(nav_tmux display -p -t "$TOWER_NAV_SESSION:0.0" '#{pane_id}')

    # 1 original run + RESPAWN_MAX respawns, then it must stay dead. Each
    # cycle is the hook's 0.5s pause plus nav-respawn.sh sourcing the libs,
    # so give the run of five plenty of room.
    _wait_for 30 _count crash $((RESPAWN_MAX + 1)) || {
        echo "runs: $(grep -c crash "$RUNLOG")" >&2
        echo "state: $(cat "$TOWER_NAV_STATE_DIR"/respawn-* 2>&1 | tr '\n' ' ')" >&2
        grep -h 'respawn' "$TOWER_LOG_FILE" >&2 || true
        nav_tmux list-panes -t "$TOWER_NAV_SESSION" -F '#{pane_index} #{pane_id} dead=#{pane_dead} [#{pane_start_command}]' >&2
        false
    }
    sleep 2
    [ "$(grep -c crash "$RUNLOG")" -eq $((RESPAWN_MAX + 1)) ]
    [ "$(nav_tmux display -p -t "$pane" '#{pane_dead}')" = 1 ]
    # The dead pane is still there for the person to look at.
    [ "$(nav_tmux list-panes -t "$TOWER_NAV_SESSION" | wc -l)" -eq 2 ]
}
