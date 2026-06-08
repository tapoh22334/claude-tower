#!/usr/bin/env bash
# tile-exit.sh - leave Tile View: disband the grid, restore each session,
# and re-enter the Navigator with the focused session selected.
#
# Invoked server-side by the tile session's `prefix+Tab` binding and its
# `client-detached` hook (both installed by tile_collapse's caller). Runs on
# the SESSION server; must NOT assume a tty until the final re-enter.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/error-recovery.sh"
source "$SCRIPT_DIR/../lib/tile.sh"

# Capture focus BEFORE teardown moves panes around.
focused=$(session_tmux display-message -p -t "$TOWER_TILE_SESSION" \
    '#{@tower_name}' 2>/dev/null || echo "")

if ! tile_disband; then
    set_nav_warning "Tile teardown incomplete — run 'make status'"
fi

[[ -n "$focused" ]] && set_nav_selected "$focused"

# Re-enter the Navigator (Tab in -> prefix+Tab out is a reversible round trip).
# Tests set TOWER_TILE_NO_REENTER to stop before the exec.
[[ -n "${TOWER_TILE_NO_REENTER:-}" ]] && exit 0
TMUX= exec "$SCRIPT_DIR/navigator.sh" --direct
