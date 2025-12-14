#!/usr/bin/env bash
# claude-tower - A session/window/pane manager with tree view and preview
# https://github.com/tapoh22334/claude-tower

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library for metadata cleanup on startup
# shellcheck source=lib/common.sh
source "$CURRENT_DIR/lib/common.sh" 2>/dev/null || true

# Default key bindings (can be overridden in .tmux.conf)
TOWER_KEY="${CLAUDE_TOWER_KEY:-C}"
TOWER_NEW_KEY="${CLAUDE_TOWER_NEW_KEY:-T}"

# Bind keys
tmux bind-key "$TOWER_KEY" run-shell "$CURRENT_DIR/scripts/tower.sh"
tmux bind-key "$TOWER_NEW_KEY" run-shell "$CURRENT_DIR/scripts/new-session.sh"

# Set environment variables for scripts
tmux set-environment -g CLAUDE_TOWER_DIR "$CURRENT_DIR"

# Ensure metadata directory exists
mkdir -p "${CLAUDE_TOWER_METADATA_DIR:-$HOME/.claude-tower/metadata}" 2>/dev/null || true
