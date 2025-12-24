#!/usr/bin/env bash
# claude-tower - Parallel Claude Code Orchestrator
# A tmux plugin for managing multiple Claude Code sessions
# https://github.com/tapoh22334/claude-tower

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=lib/common.sh
source "$CURRENT_DIR/lib/common.sh" 2>/dev/null || true

# Read tmux options with defaults
get_tmux_option() {
    local option="$1"
    local default="$2"
    local value
    value=$(tmux show-option -gqv "$option" 2>/dev/null)
    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Key bindings (configurable via tmux options)
TOWER_KEY=$(get_tmux_option "@tower-key" "${CLAUDE_TOWER_KEY:-C}")
TOWER_NEW_KEY=$(get_tmux_option "@tower-new-key" "${CLAUDE_TOWER_NEW_KEY:-T}")

# Bind keys
# prefix + C: Open Navigator (main UI)
tmux bind-key "$TOWER_KEY" run-shell "$CURRENT_DIR/scripts/tower.sh"

# prefix + T: Create new session (quick access)
tmux bind-key "$TOWER_NEW_KEY" run-shell "$CURRENT_DIR/scripts/session-new.sh"

# Set environment variables for scripts
tmux set-environment -g CLAUDE_TOWER_DIR "$CURRENT_DIR"

# Ensure directories exist
mkdir -p "${CLAUDE_TOWER_METADATA_DIR:-$HOME/.claude-tower/metadata}" 2>/dev/null || true
mkdir -p "${CLAUDE_TOWER_WORKTREE_DIR:-$HOME/.claude-tower/worktrees}" 2>/dev/null || true

# Auto-restore dormant sessions on plugin load (optional)
if [[ "$(get_tmux_option "@tower-auto-restore" "0")" == "1" ]]; then
    "$CURRENT_DIR/scripts/session-restore.sh" --all 2>/dev/null || true
fi

# Display initialization message
tmux display-message "claude-tower loaded. Press prefix + $TOWER_KEY to open Navigator" 2>/dev/null || true
