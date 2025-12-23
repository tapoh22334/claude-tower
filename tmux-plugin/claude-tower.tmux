#!/usr/bin/env bash
# claude-tower - A session/window/pane manager with tree view and preview
# https://github.com/tapoh22334/claude-tower

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library for metadata cleanup on startup
# shellcheck source=lib/common.sh
source "$CURRENT_DIR/lib/common.sh" 2>/dev/null || true

# Read key bindings from tmux options (set via @tower-key, @tower-new-key)
# Falls back to environment variables, then defaults
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

TOWER_KEY=$(get_tmux_option "@tower-key" "${CLAUDE_TOWER_KEY:-C}")
TOWER_NEW_KEY=$(get_tmux_option "@tower-new-key" "${CLAUDE_TOWER_NEW_KEY:-T}")
TOWER_SIDEBAR_KEY=$(get_tmux_option "@tower-sidebar-key" "${CLAUDE_TOWER_SIDEBAR_KEY:-S}")

# Bind keys
# prefix + C: Open full tree picker (fzf overlay)
tmux bind-key "$TOWER_KEY" run-shell "$CURRENT_DIR/scripts/tower.sh"

# prefix + T: Create new session
tmux bind-key "$TOWER_NEW_KEY" run-shell "$CURRENT_DIR/scripts/new-session.sh"

# prefix + S: Toggle sidebar
tmux bind-key "$TOWER_SIDEBAR_KEY" run-shell "$CURRENT_DIR/scripts/sidebar.sh --toggle"

# Set environment variables for scripts
tmux set-environment -g CLAUDE_TOWER_DIR "$CURRENT_DIR"

# Ensure metadata directory exists
mkdir -p "${CLAUDE_TOWER_METADATA_DIR:-$HOME/.claude-tower/metadata}" 2>/dev/null || true

# Configure status bar with tower info (optional - user can customize)
# Uncomment to enable:
# tmux set-option -g status-right '#($CURRENT_DIR/scripts/statusline.sh) | %H:%M'
