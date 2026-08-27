#!/usr/bin/env bats
# Handoff from the session list to the full-screen views (tile/tail/queue).
#
# Each of those views runs as a window on the session server, and the
# Navigator detaches the user onto that server so they land on it. Both
# halves have to name the SAME session. They did not: the window was created
# with a bare `new-window` (which lands on whatever session the server
# considers current) while the attach picked `list-sessions | head -1`. With
# more than one session those differ, and the user was dropped onto a session
# with no view window in it — the view existed, just not where they were sent.
#
# Unit tests missed this because each half is correct in isolation; only the
# pairing is wrong. These assert the pairing.

load '../test_helper'

SESSION_SOCKET="ct-viewhandoff-session"
NAV_SOCKET="ct-viewhandoff-nav"

setup_file() {
    export TMUX_TMPDIR="/tmp/claude-tower-viewhandoff-test"
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
    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
    # Three sessions: with only one, the bug is invisible because "current"
    # and "first" are the same session.
    local i
    for i in 1 2 3; do
        TMUX= tmux -L "$SESSION_SOCKET" new-session -d \
            -s "tower_0000000${i}-0000-4000-8000-00000000000${i}" \
            -c /tmp "sleep 60" 2>/dev/null || true
    done
}

teardown() {
    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
}

# Run one of the switch_* functions with the detach stubbed out, then report
# "<attach target>|<session holding the view window>".
_handoff_targets() {
    local fn="$1" window="$2"
    run bash -c '
        export CLAUDE_TOWER_SESSION_SOCKET="'"$SESSION_SOCKET"'"
        export CLAUDE_TOWER_NAV_SOCKET="'"$NAV_SOCKET"'"
        export TMUX_TMPDIR="'"$TMUX_TMPDIR"'"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/navigator-list.sh"
        set +e
        # The real detach would tear down the test client.
        nav_tmux() { :; }
        '"$fn"' >/dev/null 2>&1
        target=$(session_tmux list-sessions -F "#{session_name}" 2>/dev/null | head -1)
        holder=$(session_tmux list-windows -a -F "#{session_name}:#{window_name}" 2>/dev/null \
            | grep "'"$window"'" | head -1 | cut -d: -f1)
        printf "%s|%s\n" "$target" "$holder"
    '
}

@test "switch_to_tile: the tile window lands on the session the user is attached to" {
    _handoff_targets switch_to_tile "tower-tile"
    [ "$status" -eq 0 ]
    local target="${output%%|*}" holder="${output##*|}"
    [ -n "$target" ]
    [ -n "$holder" ]
    [ "$target" = "$holder" ]
}

@test "switch_to_tail: the tail window lands on the session the user is attached to" {
    _handoff_targets switch_to_tail "tower-tail"
    [ "$status" -eq 0 ]
    local target="${output%%|*}" holder="${output##*|}"
    [ -n "$target" ]
    [ -n "$holder" ]
    [ "$target" = "$holder" ]
}

@test "switch_to_queue: the queue window lands on the session the user is attached to" {
    _handoff_targets switch_to_queue "tower-queue"
    [ "$status" -eq 0 ]
    local target="${output%%|*}" holder="${output##*|}"
    [ -n "$target" ]
    [ -n "$holder" ]
    [ "$target" = "$holder" ]
}

@test "switch_to_tile: with no sessions at all, nothing is created and nothing crashes" {
    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
    run bash -c '
        export CLAUDE_TOWER_SESSION_SOCKET="'"$SESSION_SOCKET"'"
        export CLAUDE_TOWER_NAV_SOCKET="'"$NAV_SOCKET"'"
        export TMUX_TMPDIR="'"$TMUX_TMPDIR"'"
        source "'"$PROJECT_ROOT"'/tmux-plugin/scripts/navigator-list.sh"
        set +e
        nav_tmux() { :; }
        switch_to_tile >/dev/null 2>&1
        echo "rc=$?"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0"* ]]
}
