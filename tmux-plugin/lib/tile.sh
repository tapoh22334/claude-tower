#!/usr/bin/env bash
# tile.sh - join-pane Tile View state machine (sourced, not executed).
# Provides tile_collapse (enter) and tile_disband (exit/sweep).
# Relies on common.sh being sourced first (session_tmux, TOWER_TILE_*).

# tile_disband — return every mapped pane to its tower_X session and tear the
# tile down. Idempotent and crash-safe. Returns 0 if clean, 1 on any anomaly
# (so callers can surface a warning). Pure state repair: attaches nothing.
tile_disband() {
    [[ -f "$TOWER_TILE_MAP_FILE" ]] || return 0
    local rc=0 pane sess holder ph
    while IFS=$'\t' read -r pane sess; do
        [[ -n "$pane" && -n "$sess" ]] || continue
        if ! session_tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane"; then
            error_log "tile: pane $pane ($sess) gone (Claude exited); skipping"
            rc=1
            continue
        fi
        holder="${sess}:${TOWER_TILE_HOLDER_WINDOW}"
        if session_tmux has-session -t "$sess" 2>/dev/null; then
            # Happy path: holder kept the session alive. Break the pane out of
            # the tile into its own `claude` window, then drop the holder. We
            # must NOT join into the holder window and kill-window it: that
            # window would then hold both the holder sleep AND the Claude pane,
            # and kill-window would take the Claude pane down with it.
            if session_tmux break-pane -d -s "$pane" -n claude -t "${sess}:" 2>/dev/null; then
                session_tmux kill-window -t "$holder" 2>/dev/null || true
            else
                error_log "tile: failed to rejoin $pane into $sess"
                rc=1
            fi
        else
            # Session vanished entirely — recreate it from a placeholder, break
            # the surviving pane in as `claude`, then drop the placeholder.
            if session_tmux new-session -d -s "$sess" -n claude 2>/dev/null; then
                ph=$(session_tmux list-panes -t "${sess}:" -F '#{pane_id}' | head -1)
                session_tmux break-pane -d -s "$pane" -n claude -t "${sess}:" 2>/dev/null || rc=1
                session_tmux kill-pane -t "$ph" 2>/dev/null || true
            else
                error_log "tile: failed to recreate session $sess"
                rc=1
            fi
        fi
    done <"$TOWER_TILE_MAP_FILE"
    rm -f "$TOWER_TILE_MAP_FILE"
    if session_tmux has-session -t "$TOWER_TILE_SESSION" 2>/dev/null; then
        session_tmux kill-session -t "$TOWER_TILE_SESSION" 2>/dev/null || true
    fi
    return "$rc"
}
