#!/usr/bin/env bash
# return-to-caller.sh - Return the tmux client to the session that originally
# launched Tower.
#
# Invoked from `detach-client -E` bindings on the Navigator and Session
# servers when the user presses prefix+t to "exit Tower" from anywhere in
# the Tower world.
#
# Resolution order:
#   1. The caller session recorded by claude-tower.tmux at prefix+t time,
#      if it still exists on the default server.
#   2. Any other session on the default server.
#   3. An interactive shell as last resort (so the user is never stranded).
#
# Behaves silently — never echoes status; the user just lands where they
# should be (or in a shell if nothing else is available).

set -uo pipefail

CALLER_FILE="${CLAUDE_TOWER_CALLER_FILE:-/tmp/claude-tower/caller}"

caller=""
if [[ -r "$CALLER_FILE" ]]; then
    caller=$(<"$CALLER_FILE")
    caller="${caller//$'\n'/}"
fi

# 1. The recorded caller session, if it still exists.
if [[ -n "$caller" ]]; then
    if TMUX= tmux has-session -t "$caller" 2>/dev/null; then
        exec env TMUX= tmux attach-session -t "$caller"
    fi
fi

# 2. Any other session on the default server.
target=$(TMUX= tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || true)
if [[ -n "$target" ]]; then
    exec env TMUX= tmux attach-session -t "$target"
fi

# 3. Drop to a shell — never strand the client.
exec "${SHELL:-/bin/sh}"
