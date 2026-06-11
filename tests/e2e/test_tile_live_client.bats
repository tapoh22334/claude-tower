#!/usr/bin/env bats
# Live-client ("visual") tests for the join-pane Tile View.
#
# The other Tile suites are headless (`new-session -d`, no client) and the
# navigator-keys suite greps source — both pin structure but neither sees what
# a *person at a sized terminal* sees. The two bugs that drove the Tile rework
# only manifest with a real attached client:
#   * the pane that "shrinks one row every half second" (geometry over time)
#   * prefix+Tab quitting tmux instead of returning to the Navigator (exit path)
#
# This suite attaches a real, fixed-size client over a PTY
# (tests/helpers/pty_client.py) and, for the exit test, injects real keystrokes
# through that client's keyboard — the terminal equivalent of a browser test
# that resizes the viewport and clicks a button. Each Claude session is stood
# in by `/bin/sleep 600` so panes have a stable PID across the round trip.

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SESSION_SOCKET="ct-tilelive-sess-$$"
PTY_CLIENT="$PROJECT_ROOT/tests/helpers/pty_client.py"
TILE_EXIT="$PROJECT_ROOT/tmux-plugin/scripts/tile-exit.sh"

setup() {
    # The PTY driver needs python3 (stdlib only). Skip rather than hard-fail on
    # an environment without it; CI images install it (Dockerfile.test).
    command -v python3 >/dev/null || skip "python3 not available for PTY client"
    export TMUX_TMPDIR="/tmp/ct-tilelive-$$"
    mkdir -p "$TMUX_TMPDIR"; chmod 700 "$TMUX_TMPDIR"
    export CLAUDE_TOWER_SESSION_SOCKET="$SESSION_SOCKET"
    export TOWER_NAV_STATE_DIR_OVERRIDE="/tmp/ct-tilelive-state-$$"
    rm -rf "$TOWER_NAV_STATE_DIR_OVERRIDE"; mkdir -p "$TOWER_NAV_STATE_DIR_OVERRIDE"
    CLIENT_PIDS=()

    set +euo pipefail
    # shellcheck disable=SC1090,SC1091
    source "$PROJECT_ROOT/tmux-plugin/lib/common.sh"
    source "$PROJECT_ROOT/tmux-plugin/lib/tile.sh"
    set -euo pipefail
    trap - ERR

    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
}

teardown() {
    for p in "${CLIENT_PIDS[@]:-}"; do
        [[ -n "$p" ]] && kill "$p" 2>/dev/null || true
    done
    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
    rm -rf "$TMUX_TMPDIR" "$TOWER_NAV_STATE_DIR_OVERRIDE" 2>/dev/null || true
}

make_claude() {
    local name="$1"
    TMUX= tmux -L "$SESSION_SOCKET" new-session -d -s "tower_${name}" \
        -x 200 -y 50 "exec /bin/sleep 600"
}

# Attach a real fixed-size client over a PTY and wait until the server reports
# it. An optional 4th arg is an input FIFO the client forwards as keystrokes.
# Records the PID for teardown.
attach_client() {
    local target="$1" cols="$2" rows="$3" fifo="${4:-}"
    python3 "$PTY_CLIENT" "$SESSION_SOCKET" "$target" "$cols" "$rows" "$fifo" &
    CLIENT_PIDS+=("$!")
    local i n
    for i in $(seq 1 50); do
        n=$(TMUX= tmux -L "$SESSION_SOCKET" list-clients -t "$target" 2>/dev/null | wc -l)
        [[ "$n" -ge 1 ]] && return 0
        sleep 0.1
    done
    return 1
}

# Smallest pane height in the tile, right now.
min_tile_height() {
    TMUX= tmux -L "$SESSION_SOCKET" list-panes -t "$TOWER_TILE_SESSION" \
        -F '#{pane_height}' 2>/dev/null | sort -n | head -1
}

# ============================================================================
# Geometry: the pane must not march toward a single row under a live client.
# ============================================================================

@test "tile geometry: pane height holds steady under an attached client" {
    make_claude one; make_claude two; make_claude three
    tile_collapse
    attach_client "$TOWER_TILE_SESSION" 200 50

    sleep 0.5                       # let the first frame settle
    local start; start=$(min_tile_height)
    [ "$start" -ge 5 ]              # a real client gives every pane real estate

    # Watch ~2.5s: the old nested-attach Tile lost ~1 row per 0.5s; a stable
    # Tile keeps its height. Require it never drops below the start.
    local i now
    for i in $(seq 1 5); do
        sleep 0.5
        now=$(min_tile_height)
        [ "$now" -ge "$start" ]
    done

    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-clients -t "$TOWER_TILE_SESSION" | wc -l)" -ge 1 ]
    [ "$now" -ge 5 ]
}

@test "tile geometry: a second, smaller client does not collapse the panes" {
    make_claude a; make_claude b
    tile_collapse
    attach_client "$TOWER_TILE_SESSION" 200 50
    attach_client "$TOWER_TILE_SESSION" 120 30

    sleep 0.5
    local start; start=$(min_tile_height)
    [ "$start" -ge 5 ]

    local i now
    for i in $(seq 1 4); do
        sleep 0.5
        now=$(min_tile_height)
        [ "$now" -ge "$start" ]
    done
    [ "$now" -ge 5 ]
}

# ============================================================================
# Exit: a real client pressing prefix+Tab must tear the Tile down through the
# detach-client -E path (carrying its tty) — not drop the client / quit tmux.
# The static binding-string invariant is pinned in test_navigator_new_keys.bats;
# here we drive the *live* path end to end. Nav re-entry is suppressed with
# TOWER_TILE_NO_REENTER (it needs the separate Navigator server).
# ============================================================================

@test "tile exit: real client prefix+Tab disbands the tile and restores sessions" {
    make_claude p; make_claude q
    local orig_p
    orig_p=$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower_p: -F '#{pane_pid}')

    # Deterministic prefix so the injected keystroke is stable regardless of the
    # host's ~/.tmux.conf (which may remap prefix, e.g. to C-s).
    TMUX= tmux -L "$SESSION_SOCKET" set-option -g prefix C-b
    tile_collapse

    # Production-shape exit binding: detach-client -E carries the tty across
    # teardown (the regression fixed in b418eb3). run-shell -b here would run
    # tty-less and drop the client.
    TMUX= tmux -L "$SESSION_SOCKET" bind-key Tab \
        detach-client -E "TOWER_TILE_NO_REENTER=1 exec '$TILE_EXIT'"

    local fifo="$TMUX_TMPDIR/keys"
    mkfifo "$fifo"
    # If the client cannot attach, fail here — never fall through to the FIFO
    # write below, which would block forever on a reader-less pipe.
    attach_client "$TOWER_TILE_SESSION" 200 50 "$fifo"

    # Press prefix (C-b = 0x02) then Tab (0x09), as real keyboard input. Bound
    # the write with timeout so a missing reader can never hang the suite.
    timeout 5 bash -c "printf '\\002\\t' > '$fifo'"

    # The tile must disband.
    local i gone=
    for i in $(seq 1 50); do
        if ! TMUX= tmux -L "$SESSION_SOCKET" has-session -t "$TOWER_TILE_SESSION" 2>/dev/null; then
            gone=1; break
        fi
        sleep 0.1
    done
    [ -n "$gone" ]

    # Sessions restored, original Claude pane PID broken back into tower_p,
    # and the sessions server itself survived (the bug quit it).
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_p
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_q
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower_p: -F '#{pane_pid}')" = "$orig_p" ]
}
