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
    cat <<'EOF'
Create a new claude-tower session

Usage: session-new.sh [options]

Options:
  -n, --name NAME     Session name (required)
  -w, --worktree      Create worktree session (persistent)
  -d, --dir DIR       Working directory (default: current)
  --no-attach         Don't switch/attach to new session (for Navigator)
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
no_attach=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n | --name)
            name="$2"
            shift 2
            ;;
        -w | --worktree)
            use_worktree=true
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
    # Pure bash input (works in display-popup)
    echo -e "${C_HEADER}Create New Session${C_RESET}"
    echo ""
    echo -e "Session Types:"
    echo -e "  ${C_GREEN}[S] Simple${C_RESET}    - Volatile, lost on tmux restart"
    echo -e "  ${C_YELLOW}[W] Worktree${C_RESET}  - Persistent with git worktree"
    echo ""
    read -r -p "Session name: " name

    if [[ -z "$name" ]]; then
        exit 0 # User cancelled
    fi

    # Ask for type if not specified
    if [[ "$use_worktree" == "false" ]]; then
        echo ""
        read -r -p "Create as worktree? [y/N]: " worktree_choice
        [[ "$worktree_choice" =~ ^[Yy] ]] && use_worktree=true
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

# Determine session type
if [[ "$use_worktree" == "true" ]]; then
    session_type="$TYPE_WORKTREE"
else
    session_type="$TYPE_SIMPLE"
fi

# Create session
debug_log "Creating session: name=$name, type=$session_type, dir=$working_dir"

if create_session "$name" "$session_type" "$working_dir"; then
    # Switch to new session on session server (unless --no-attach)
    if [[ "$no_attach" != "true" ]]; then
        session_id=$(normalize_session_name "$(sanitize_name "$name")")
        session_tmux switch-client -t "$session_id" 2>/dev/null ||
            session_tmux attach-session -t "$session_id" 2>/dev/null || true
    fi
else
    exit 1
fi
