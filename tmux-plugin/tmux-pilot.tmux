#!/usr/bin/env bash
# tmux-pilot - A session/window/pane manager with tree view and preview
# https://github.com/your-username/tmux-pilot

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default key bindings (can be overridden in .tmux.conf)
PILOT_KEY="${TMUX_PILOT_KEY:-p}"
PILOT_NEW_KEY="${TMUX_PILOT_NEW_KEY:-P}"

# Bind keys
tmux bind-key "$PILOT_KEY" run-shell "$CURRENT_DIR/scripts/pilot.sh"
tmux bind-key "$PILOT_NEW_KEY" run-shell "$CURRENT_DIR/scripts/new-session.sh"

# Set environment variables for scripts
tmux set-environment -g TMUX_PILOT_DIR "$CURRENT_DIR"
