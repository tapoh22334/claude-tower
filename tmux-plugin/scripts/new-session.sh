#!/usr/bin/env bash
# Create a new session (Workspace mode for git repos, Simple mode otherwise)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

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

    # Sanitize session name to prevent path traversal and command injection
    local sanitized_name
    sanitized_name=$(sanitize_name "$name")
    if [[ -z "$sanitized_name" ]]; then
        handle_error "Invalid session name"
        return 1
    fi

    printf "%b%s%b\n" "$C_BLUE" "Creating Workspace session: $sanitized_name" "$C_RESET"

    # Get current branch as base
    local base_branch
    base_branch=$(git -C "$repo_path" branch --show-current 2>/dev/null || echo "main")
    local base_commit
    base_commit=$(git -C "$repo_path" rev-parse HEAD 2>/dev/null)

    # Create branch name
    local branch_name="pilot/${sanitized_name}"

    # Create worktree directory
    local worktree_path="${PILOT_WORKTREE_DIR}/${sanitized_name}"

    # Validate worktree path is within expected directory (prevent path traversal)
    if ! validate_path_within "$worktree_path" "$PILOT_WORKTREE_DIR"; then
        handle_error "Invalid worktree path"
        return 1
    fi

    mkdir -p "$(dirname "$worktree_path")"

    # Check if worktree already exists
    if [[ -d "$worktree_path" ]]; then
        printf "%b%s%b\n" "$C_YELLOW" "Worktree already exists, using it" "$C_RESET"
    else
        # Create new worktree with new branch
        if git -C "$repo_path" worktree add -b "$branch_name" "$worktree_path" "$base_commit" 2>/dev/null; then
            printf "%b%s%b\n" "$C_GREEN" "Created worktree at: $worktree_path" "$C_RESET"
        else
            # Branch might exist, try without -b
            if git -C "$repo_path" worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
                printf "%b%s%b\n" "$C_GREEN" "Using existing branch: $branch_name" "$C_RESET"
            else
                handle_error "Failed to create worktree"
                return 1
            fi
        fi
    fi

    # Create tmux session in worktree
    local session_name
    session_name=$(normalize_session_name "$sanitized_name")

    if tmux has-session -t "$session_name" 2>/dev/null; then
        printf "%b%s%b\n" "$C_YELLOW" "Session exists, switching to it" "$C_RESET"
        tmux switch-client -t "$session_name"
    else
        tmux new-session -d -s "$session_name" -c "$worktree_path" "$PILOT_PROGRAM"
        # Store metadata in tmux options
        tmux set-option -t "$session_name" @pilot_mode "workspace"
        tmux set-option -t "$session_name" @pilot_repo "$repo_path"
        tmux set-option -t "$session_name" @pilot_base "$base_commit"
        # Save metadata to file for persistence
        save_metadata "$session_name" "workspace" "$repo_path" "$base_commit"
        tmux switch-client -t "$session_name"
        printf "%b%s%b\n" "$C_GREEN" "Switched to new session: $session_name" "$C_RESET"
    fi
}

# Create simple session (non-git)
create_simple_session() {
    local name="$1"
    local dir="$CURRENT_DIR"

    # Sanitize session name
    local sanitized_name
    sanitized_name=$(sanitize_name "$name")
    if [[ -z "$sanitized_name" ]]; then
        handle_error "Invalid session name"
        return 1
    fi

    printf "%b%s%b\n" "$C_BLUE" "Creating Simple session: $sanitized_name" "$C_RESET"

    local session_name
    session_name=$(normalize_session_name "$sanitized_name")

    if tmux has-session -t "$session_name" 2>/dev/null; then
        printf "%b%s%b\n" "$C_YELLOW" "Session exists, switching to it" "$C_RESET"
        tmux switch-client -t "$session_name"
    else
        tmux new-session -d -s "$session_name" -c "$dir" "$PILOT_PROGRAM"
        tmux set-option -t "$session_name" @pilot_mode "simple"
        # Save metadata to file for persistence
        save_metadata "$session_name" "simple"
        tmux switch-client -t "$session_name"
        printf "%b%s%b\n" "$C_GREEN" "Switched to new session: $session_name" "$C_RESET"
    fi
}

# Main
main() {
    local name
    name=$(get_session_name)

    if [[ -z "$name" ]]; then
        handle_info "Cancelled"
        exit 0
    fi

    # Check if current directory is a git repo
    if git -C "$CURRENT_DIR" rev-parse --git-dir &>/dev/null; then
        create_workspace_session "$name"
    else
        create_simple_session "$name"
    fi
}

main
