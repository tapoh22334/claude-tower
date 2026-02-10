#!/usr/bin/env bash
# session-new.sh - Create a new claude-tower session
#
# DEPRECATED (v2): Use 'tower add <path>' instead.
# This script is kept for backward compatibility.
#
# Usage: session-new.sh [options]
#   -n, --name NAME     Session name (required)
#   -w, --worktree      DEPRECATED: Ignored (all sessions are now directory-based)
#   -d, --dir DIR       Working directory (default: current)
#   -h, --help          Show help
#
# Note: -w/--worktree option is ignored in v2 (all sessions are now simple).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="session-new.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

show_help() {
    cat <<'EOF'
Create a new claude-tower session (DEPRECATED)

NOTICE: This command is deprecated. Use 'tower add' instead.

Usage: session-new.sh [options]

Options:
  -n, --name NAME     Session name (required)
  -d, --dir DIR       Working directory (default: current)
  --no-attach         Don't switch/attach to new session (for Navigator)
  -h, --help          Show this help

Examples:
  session-new.sh -n my-feature              # Session in current dir
  session-new.sh -n experiment -d ~/projects/app

  Recommended (new syntax):
  tower add ~/projects/app -n my-feature

EOF
}

# Parse arguments
name=""
working_dir=""
no_attach=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n | --name)
            name="$2"
            shift 2
            ;;
        -w | --worktree)
            # DEPRECATED: Ignored for backwards compatibility
            shift
            ;;
        -d | --dir)
            working_dir="$2"
            shift 2
            ;;
        --no-attach)
            no_attach=true
            shift
            ;;
        -h | --help)
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
    echo -e "${C_HEADER}Create New Session${C_RESET}"
    echo ""
    read -r -p "Session name: " name

    if [[ -z "$name" ]]; then
        exit 0 # User cancelled
    fi
fi

if [[ -z "$name" ]]; then
    handle_error "Session name is required"
    exit 1
fi

# Determine working directory
if [[ -z "$working_dir" ]]; then
    # Try to get from current tmux pane
    # First try session server (for tower_* sessions), then fall back to default server
    working_dir=$(session_tmux display-message -p '#{pane_current_path}' 2>/dev/null) ||
        working_dir=$(TMUX= tmux display-message -p '#{pane_current_path}' 2>/dev/null) ||
        working_dir=$(pwd)
fi

# Create session (v2 format: name + directory only)
debug_log "Creating session: name=$name, dir=$working_dir"

if create_session "$name" "$working_dir"; then
    # Switch to new session on session server (unless --no-attach)
    if [[ "$no_attach" != "true" ]]; then
        session_id=$(normalize_session_name "$(sanitize_name "$name")")
        session_tmux switch-client -t "$session_id" 2>/dev/null ||
            session_tmux attach-session -t "$session_id" 2>/dev/null || true
    fi
else
    exit 1
fi
