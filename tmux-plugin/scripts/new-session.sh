#!/usr/bin/env bash
# Create a new session (Workspace mode for git repos, Simple mode otherwise)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="new-session.sh"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Check dependencies
require_command fzf || exit 1

# Get current directory
CURRENT_DIR=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null || pwd)
debug_log "Current directory: $CURRENT_DIR"

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
    local repository_path="$CURRENT_DIR"

    debug_log "Creating workspace session: $name in $repository_path"

    # Sanitize session name to prevent path traversal and command injection
    local sanitized_name
    sanitized_name=$(sanitize_name "$name")
    if [[ -z "$sanitized_name" ]]; then
        handle_error "Invalid session name: contains only invalid characters"
        return 1
    fi

    if ! validate_session_name "$sanitized_name"; then
        handle_error "Invalid session name format"
        return 1
    fi

    printf "%b%s%b\n" "$C_BLUE" "Creating Workspace session: $sanitized_name" "$C_RESET"

    # Get current branch as source
    local source_branch
    source_branch=$(git -C "$repository_path" branch --show-current 2>/dev/null || echo "main")
    local source_commit
    source_commit=$(git -C "$repository_path" rev-parse HEAD 2>/dev/null)

    if [[ -z "$source_commit" ]]; then
        handle_error "Failed to get current commit. Is this a valid git repository?"
        return 1
    fi

    debug_log "Source branch: $source_branch, commit: $source_commit"

    # Create branch name
    local branch_name="tower/${sanitized_name}"

    # Create worktree directory
    local worktree_path="${TOWER_WORKTREE_DIR}/${sanitized_name}"

    # Validate worktree path is within expected directory (prevent path traversal)
    if ! validate_path_within "$worktree_path" "$TOWER_WORKTREE_DIR"; then
        handle_error "Invalid worktree path: path traversal detected"
        return 1
    fi

    if ! mkdir -p "$(dirname "$worktree_path")"; then
        handle_error "Failed to create worktree directory"
        return 1
    fi

    # Check if worktree already exists
    if [[ -d "$worktree_path" ]]; then
        handle_warning "Worktree already exists, using it"
    else
        # Create new worktree with new branch
        local git_output
        if git_output=$(git -C "$repository_path" worktree add -b "$branch_name" "$worktree_path" "$source_commit" 2>&1); then
            handle_success "Created worktree at: $worktree_path"
            debug_log "Git output: $git_output"
        else
            debug_log "First worktree attempt failed: $git_output"
            # Branch might exist, try without -b
            if git_output=$(git -C "$repository_path" worktree add "$worktree_path" "$branch_name" 2>&1); then
                handle_success "Using existing branch: $branch_name"
            else
                handle_error "Failed to create worktree: $git_output"
                return 1
            fi
        fi
    fi

    # Create tmux session in worktree
    local session_id
    session_id=$(normalize_session_name "$sanitized_name")

    if session_exists "$session_id"; then
        handle_warning "Session '$session_id' exists, switching to it"
        if ! safe_tmux switch-client -t "$session_id"; then
            handle_error "Failed to switch to session: $session_id"
            return 1
        fi
    else
        debug_log "Creating new tmux session: $session_id"
        if ! tmux new-session -d -s "$session_id" -c "$worktree_path" "$TOWER_PROGRAM"; then
            handle_error "Failed to create tmux session"
            return 1
        fi
        # Store metadata in tmux options
        tmux set-option -t "$session_id" @tower_session_type "workspace"
        tmux set-option -t "$session_id" @tower_repository "$repository_path"
        tmux set-option -t "$session_id" @tower_source "$source_commit"
        # Save metadata to file for persistence
        save_metadata "$session_id" "workspace" "$repository_path" "$source_commit"

        if ! safe_tmux switch-client -t "$session_id"; then
            handle_error "Failed to switch to new session"
            return 1
        fi
        handle_success "Created session: $session_id"
    fi
}

# Create simple session (non-git)
create_simple_session() {
    local name="$1"
    local working_directory="$CURRENT_DIR"

    debug_log "Creating simple session: $name in $working_directory"

    # Sanitize session name
    local sanitized_name
    sanitized_name=$(sanitize_name "$name")
    if [[ -z "$sanitized_name" ]]; then
        handle_error "Invalid session name: contains only invalid characters"
        return 1
    fi

    if ! validate_session_name "$sanitized_name"; then
        handle_error "Invalid session name format"
        return 1
    fi

    printf "%b%s%b\n" "$C_BLUE" "Creating Simple session: $sanitized_name" "$C_RESET"

    local session_id
    session_id=$(normalize_session_name "$sanitized_name")

    if session_exists "$session_id"; then
        handle_warning "Session '$session_id' exists, switching to it"
        if ! safe_tmux switch-client -t "$session_id"; then
            handle_error "Failed to switch to session: $session_id"
            return 1
        fi
    else
        debug_log "Creating new tmux session: $session_id"
        if ! tmux new-session -d -s "$session_id" -c "$working_directory" "$TOWER_PROGRAM"; then
            handle_error "Failed to create tmux session"
            return 1
        fi
        tmux set-option -t "$session_id" @tower_session_type "simple"
        # Save metadata to file for persistence
        save_metadata "$session_id" "simple"

        if ! safe_tmux switch-client -t "$session_id"; then
            handle_error "Failed to switch to new session"
            return 1
        fi
        handle_success "Created session: $session_id"
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
