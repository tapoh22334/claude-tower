#!/usr/bin/env bash
# session-new.sh - Create a new claude-tower session
# Usage: session-new.sh [options]
#   -n, --name NAME     Session name (required)
#   -w, --worktree      Create worktree session (persistent)
#   -d, --dir DIR       Working directory (default: current)
#   -h, --help          Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="session-new.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

show_help() {
    cat << 'EOF'
Create a new claude-tower session

Usage: session-new.sh [options]

Options:
  -n, --name NAME     Session name (required)
  -w, --worktree      Create worktree session (persistent)
  -d, --dir DIR       Working directory (default: current)
  -h, --help          Show this help

Session Types:
  Simple (default)    Volatile session, lost on tmux restart
  Worktree (-w)       Persistent session with git worktree, auto-restores

Examples:
  session-new.sh -n my-feature              # Simple session in current dir
  session-new.sh -n my-feature -w           # Worktree session from current repo
  session-new.sh -n experiment -d ~/projects/app

EOF
}

# Parse arguments
name=""
use_worktree=false
working_dir=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--name)
            name="$2"
            shift 2
            ;;
        -w|--worktree)
            use_worktree=true
            shift
            ;;
        -d|--dir)
            working_dir="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            handle_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Interactive mode if no name provided
if [[ -z "$name" ]]; then
    # Use fzf for input
    if command -v fzf &>/dev/null; then
        name=$(echo "" | fzf-tmux -p 60%,30% \
            --print-query \
            --header="Enter session name:" \
            --prompt="Name: " \
            --no-info \
            2>/dev/null | head -1) || true
    else
        handle_error "Session name is required (-n NAME)"
        exit 1
    fi
fi

if [[ -z "$name" ]]; then
    handle_error "Session name is required"
    exit 1
fi

# Determine working directory
if [[ -z "$working_dir" ]]; then
    # Try to get from current tmux pane
    working_dir=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || pwd)
fi

# Determine session type
if [[ "$use_worktree" == "true" ]]; then
    session_type="$TYPE_WORKTREE"
else
    session_type="$TYPE_SIMPLE"
fi

# Create session
debug_log "Creating session: name=$name, type=$session_type, dir=$working_dir"

if create_session "$name" "$session_type" "$working_dir"; then
    # Switch to new session
    session_id=$(normalize_session_name "$(sanitize_name "$name")")
    tmux switch-client -t "$session_id" 2>/dev/null || \
    tmux attach-session -t "$session_id" 2>/dev/null || true
else
    exit 1
fi
