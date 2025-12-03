#!/usr/bin/env bash
# Create a new session (Workspace mode for git repos, Simple mode otherwise)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Config
PILOT_WORKTREE_DIR="${TMUX_PILOT_WORKTREE_DIR:-$HOME/.tmux-pilot/worktrees}"
PILOT_PROGRAM="${TMUX_PILOT_PROGRAM:-claude}"

# Colors
C_RESET="\033[0m"
C_GREEN="\033[0;32m"
C_YELLOW="\033[0;33m"
C_BLUE="\033[0;34m"
C_RED="\033[0;31m"

# Get current directory
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || pwd)

# Prompt for session name
get_session_name() {
    local default_name
    default_name=$(basename "$CURRENT_DIR")

    # Use fzf-tmux as input
    echo "" | fzf-tmux -p 50%,20% \
        --print-query \
        --prompt="Session name: " \
        --header="Enter session name (default: $default_name)" \
        --bind="enter:accept-or-print-query" \
    | head -1 || echo "$default_name"
}

# Create workspace session (git repo)
create_workspace_session() {
    local name="$1"
    local repo_path="$CURRENT_DIR"

    echo -e "${C_BLUE}Creating Workspace session: $name${C_RESET}"

    # Get current branch as base
    local base_branch
    base_branch=$(git -C "$repo_path" branch --show-current 2>/dev/null || echo "main")
    local base_commit
    base_commit=$(git -C "$repo_path" rev-parse HEAD 2>/dev/null)

    # Create branch name
    local branch_name="pilot/${name}"

    # Create worktree directory
    local worktree_path="${PILOT_WORKTREE_DIR}/${name}"
    mkdir -p "$(dirname "$worktree_path")"

    # Check if worktree already exists
    if [[ -d "$worktree_path" ]]; then
        echo -e "${C_YELLOW}Worktree already exists, using existing...${C_RESET}"
    else
        # Create new worktree with new branch
        if git -C "$repo_path" worktree add -b "$branch_name" "$worktree_path" "$base_commit" 2>/dev/null; then
            echo -e "${C_GREEN}Created worktree at: $worktree_path${C_RESET}"
        else
            # Branch might exist, try without -b
            if git -C "$repo_path" worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
                echo -e "${C_GREEN}Using existing branch: $branch_name${C_RESET}"
            else
                echo -e "${C_RED}Failed to create worktree${C_RESET}"
                return 1
            fi
        fi
    fi

    # Create tmux session in worktree
    local session_name="pilot_${name}"
    session_name=$(echo "$session_name" | tr ' .' '_')

    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo -e "${C_YELLOW}Session already exists, switching...${C_RESET}"
        tmux switch-client -t "$session_name"
    else
        tmux new-session -d -s "$session_name" -c "$worktree_path" "$PILOT_PROGRAM"
        # Store metadata
        tmux set-option -t "$session_name" @pilot_mode "workspace"
        tmux set-option -t "$session_name" @pilot_repo "$repo_path"
        tmux set-option -t "$session_name" @pilot_base "$base_commit"
        tmux switch-client -t "$session_name"
        echo -e "${C_GREEN}Created and switched to session: $session_name${C_RESET}"
    fi
}

# Create simple session (non-git)
create_simple_session() {
    local name="$1"
    local dir="$CURRENT_DIR"

    echo -e "${C_BLUE}Creating Simple session: $name${C_RESET}"

    local session_name="pilot_${name}"
    session_name=$(echo "$session_name" | tr ' .' '_')

    if tmux has-session -t "$session_name" 2>/dev/null; then
        echo -e "${C_YELLOW}Session already exists, switching...${C_RESET}"
        tmux switch-client -t "$session_name"
    else
        tmux new-session -d -s "$session_name" -c "$dir" "$PILOT_PROGRAM"
        tmux set-option -t "$session_name" @pilot_mode "simple"
        tmux switch-client -t "$session_name"
        echo -e "${C_GREEN}Created and switched to session: $session_name${C_RESET}"
    fi
}

# Main
main() {
    local name
    name=$(get_session_name)

    if [[ -z "$name" ]]; then
        tmux display-message "Cancelled"
        exit 0
    fi

    # Check if current directory is a git repo
    if git -C "$CURRENT_DIR" rev-parse --git-dir &>/dev/null 2>&1; then
        create_workspace_session "$name"
    else
        create_simple_session "$name"
    fi
}

main
