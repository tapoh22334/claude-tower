#!/usr/bin/env bash
# claude-tower - Parallel Claude Code Orchestrator
# A tmux plugin for managing multiple Claude Code sessions
# https://github.com/tapoh22334/claude-tower

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Note: We don't source common.sh here because:
# 1. It sets strict mode (set -euo pipefail) which affects the plugin context
# 2. The plugin only needs basic functionality that tmux provides
# Scripts source common.sh themselves when needed

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

# Tower prefix key (default: t)
# Usage: prefix + t, then next key
TOWER_PREFIX=$(get_tmux_option "@tower-prefix" "${CLAUDE_TOWER_PREFIX:-t}")

# Create tower key table
# prefix + t → enter tower mode, then:
#   c → Navigator (Claude sessions)
#   t → New session (Tower new)
#   n → New session (alias)
#   l → List sessions
#   r → Restore sessions
#   ? → Help

tmux bind-key "$TOWER_PREFIX" switch-client -T tower

# Tower mode bindings
# Navigator now uses dedicated tmux session (no popup, no external deps)
tmux bind-key -T tower c run-shell -b "$CURRENT_DIR/scripts/navigator.sh"
tmux bind-key -T tower t new-window -n "tower-new" "$CURRENT_DIR/scripts/session-new.sh"
tmux bind-key -T tower n new-window -n "tower-new" "$CURRENT_DIR/scripts/session-new.sh"
tmux bind-key -T tower l new-window -n "tower-list" "$CURRENT_DIR/scripts/session-list.sh pretty"
tmux bind-key -T tower r run-shell -b "$CURRENT_DIR/scripts/session-restore.sh --all"
tmux bind-key -T tower '?' display-message "tower: c=navigator t/n=new l=list r=restore"

# Escape from tower mode (automatic after any key, but explicit Escape too)
tmux bind-key -T tower Escape switch-client -T prefix

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
tmux display-message "claude-tower loaded. Press prefix + $TOWER_PREFIX, then c/t/n/l/r/?" 2>/dev/null || true
