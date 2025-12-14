#!/usr/bin/env bash
# tmux-pilot - A session/window/pane manager with tree view and preview
# https://github.com/claude-pilot/claude-pilot

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library for metadata cleanup on startup
# shellcheck source=lib/common.sh
source "$CURRENT_DIR/lib/common.sh" 2>/dev/null || true

# Default key bindings (can be overridden in .tmux.conf)
PILOT_KEY="${TMUX_PILOT_KEY:-C}"
PILOT_NEW_KEY="${TMUX_PILOT_NEW_KEY:-T}"

# Bind keys
tmux bind-key "$PILOT_KEY" run-shell "$CURRENT_DIR/scripts/pilot.sh"
tmux bind-key "$PILOT_NEW_KEY" run-shell "$CURRENT_DIR/scripts/new-session.sh"

# Set environment variables for scripts
tmux set-environment -g TMUX_PILOT_DIR "$CURRENT_DIR"

# Ensure metadata directory exists
mkdir -p "${TMUX_PILOT_METADATA_DIR:-$HOME/.tmux-pilot/metadata}" 2>/dev/null || true
