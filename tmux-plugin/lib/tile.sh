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

# TILE_SKIPPED is set by tile_collapse to the count of sessions excluded
# because they had more than one window (Bug 1 guard). In production callers
# invoke tile_collapse directly, so the in-memory value is authoritative. It is
# additionally mirrored to a sidecar file so callers that run tile_collapse in a
# subshell (notably bats' `run`, which forks) can still observe the count.
TILE_SKIPPED=0

# Sidecar path mirroring TILE_SKIPPED (lives beside the tile map).
_tile_skipped_file() {
    printf '%s' "$(dirname "$TOWER_TILE_MAP_FILE")/tile.skipped"
}

# Persist TILE_SKIPPED so it survives a subshell boundary.
_tile_write_skipped() {
    mkdir -p "$(dirname "$TOWER_TILE_MAP_FILE")" 2>/dev/null || true
    printf '%s\n' "$TILE_SKIPPED" >"$(_tile_skipped_file)" 2>/dev/null || true
}

# Refresh TILE_SKIPPED from the sidecar when present (no-op otherwise). Only
# wired up under bats — see below — so production scripts that source this lib
# are never burdened with a DEBUG trap.
_tile_sync_skipped() {
    local f
    f="$(_tile_skipped_file)"
    [[ -f "$f" ]] || return 0
    local v
    v="$(cat "$f" 2>/dev/null)"
    [[ "$v" =~ ^[0-9]+$ ]] && TILE_SKIPPED="$v"
    return 0
}

# Under bats, `run tile_collapse` executes in a subshell and the in-memory
# TILE_SKIPPED set there is discarded. Mirror it back in the test shell via a
# DEBUG trap. Guarded on BATS_VERSION so it never installs in production.
if [[ -n "${BATS_VERSION:-}" ]]; then
    trap '_tile_sync_skipped' DEBUG
fi

# tile_collapse — move every single-window active tower_X's claude pane into a
# dedicated tower-tile grid. Idempotent (disbands any prior tile first). Sets
# TILE_SKIPPED. Returns 0 on success, 1 if there is nothing to tile.
tile_collapse() {
    mkdir -p "$(dirname "$TOWER_TILE_MAP_FILE")" 2>/dev/null || true
    TILE_SKIPPED=0

    # 0. Recover from any prior/interrupted tile before rebuilding (NEVER a
    #    plain kill — that would strand already-joined panes).
    tile_disband || true
    if session_tmux has-session -t "$TOWER_TILE_SESSION" 2>/dev/null; then
        session_tmux kill-session -t "$TOWER_TILE_SESSION" 2>/dev/null || true
    fi

    # 1. Collect tileable sessions: active tower_* with exactly ONE window.
    local sessions=() s wins
    while IFS= read -r s; do
        [[ "$s" == tower_* ]] || continue
        [[ "$s" == "$TOWER_TILE_SESSION" ]] && continue
        wins=$(session_tmux list-windows -t "$s" -F x 2>/dev/null | wc -l)
        if [[ "$wins" -ne 1 ]]; then
            TILE_SKIPPED=$((TILE_SKIPPED + 1))
            continue
        fi
        sessions+=("$s")
    done < <(session_tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)

    if [[ ${#sessions[@]} -eq 0 ]]; then
        _tile_write_skipped
        return 1
    fi

    # 2. Dedicated tile session + a holder pane we kill once panes are joined.
    session_tmux new-session -d -s "$TOWER_TILE_SESSION" -n tile \
        -x "$(tput cols 2>/dev/null || echo 200)" \
        -y "$(tput lines 2>/dev/null || echo 50)"
    local holder tw
    holder=$(session_tmux display-message -p -t "$TOWER_TILE_SESSION" '#{pane_id}')
    tw=$(session_tmux display-message -p -t "$TOWER_TILE_SESSION" '#{window_id}')

    # Orientation cues (the deleted tile-pane.conf had turned these off).
    session_tmux set-option -t "$TOWER_TILE_SESSION" pane-border-status top 2>/dev/null || true
    session_tmux set-option -t "$TOWER_TILE_SESSION" pane-border-format ' #{@tower_name} ' 2>/dev/null || true
    session_tmux set-option -t "$TOWER_TILE_SESSION" pane-active-border-style 'fg=green,bold' 2>/dev/null || true
    session_tmux set-option -w -t "$tw" monitor-activity on 2>/dev/null || true

    # 3. For each session: explicit claude pane, holder FIRST, tag, record,
    #    join, and re-tile after EVERY join (Bug 3: join-then-tile-once fails
    #    "pane too small" at N>=4).
    : >"${TOWER_TILE_MAP_FILE}.tmp"
    local p
    for s in "${sessions[@]}"; do
        p=$(session_tmux list-panes -t "${s}:claude" -F '#{pane_id}' 2>/dev/null | head -1)
        [[ -n "$p" ]] || continue
        session_tmux new-window -d -t "$s" -n "$TOWER_TILE_HOLDER_WINDOW" \
            "exec sleep 2147483647"
        session_tmux set-option -p -t "$p" @tower_name "$s"
        printf '%s\t%s\n' "$p" "$s" >>"${TOWER_TILE_MAP_FILE}.tmp"
        session_tmux join-pane -s "$p" -t "$tw"
        session_tmux select-layout -t "$tw" tiled
    done
    mv "${TOWER_TILE_MAP_FILE}.tmp" "$TOWER_TILE_MAP_FILE"

    # 4. Drop holder, final layout, focus first pane.
    session_tmux kill-pane -t "$holder" 2>/dev/null || true
    session_tmux select-layout -t "$tw" tiled
    session_tmux select-pane -t "${tw}.0" 2>/dev/null || true
    _tile_write_skipped
    return 0
}
