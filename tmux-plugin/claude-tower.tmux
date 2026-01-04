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
# Usage: prefix + t → Navigator (direct)
TOWER_PREFIX=$(get_tmux_option "@tower-prefix" "${CLAUDE_TOWER_PREFIX:-t}")

# Direct Navigator launch with prefix + t
# Navigator uses a wrapper script for seamless server switching:
#   1. run-shell expands #{session_name} and writes caller to state file
#   2. detach-client -E runs navigator.sh which reads the caller from state
# Note: detach-client -E does NOT expand tmux format strings in its command
#
# All operations (new session, restore, etc.) are now done within Navigator:
#   n → New session
#   r → Restore selected dormant session
#   R → Restore all dormant sessions
#   d → Delete session
#   ? → Help
tmux bind-key "$TOWER_PREFIX" run-shell -b "mkdir -p /tmp/claude-tower && echo '#{session_name}' > /tmp/claude-tower/caller && tmux detach-client -E 'exec $CURRENT_DIR/scripts/navigator.sh --direct'"

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
tmux display-message "claude-tower loaded. Press prefix + $TOWER_PREFIX to open Navigator" 2>/dev/null || true
