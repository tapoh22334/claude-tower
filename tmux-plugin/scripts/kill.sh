#!/usr/bin/env bash
# Kill session, window, or pane

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

INPUT="$1"
IFS=':' read -r type session window pane _ <<< "$INPUT"

cleanup_worktree() {
    local session_name="$1"

    # Get stored repo path
    local repo_path
    repo_path=$(tmux show-option -t "$session_name" -qv @tower_repo 2>/dev/null || echo "")

    if [[ -n "$repo_path" ]]; then
        # Extract name from session (remove tower_ prefix)
        local name="${session_name#tower_}"
        local worktree_path="${TOWER_WORKTREE_DIR}/${name}"

        if [[ -d "$worktree_path" ]]; then
            # Validate path before removal
            if validate_path_within "$worktree_path" "$TOWER_WORKTREE_DIR"; then
                # Remove worktree
                if git -C "$repo_path" worktree remove "$worktree_path" 2>/dev/null; then
                    handle_info "Removed worktree: $worktree_path"
                else
                    # Force remove if normal removal fails
                    git -C "$repo_path" worktree remove --force "$worktree_path" 2>/dev/null || true
                    handle_warning "Force removed worktree: $worktree_path"
                fi
            else
                handle_error "Invalid worktree path, skipping cleanup"
            fi
        fi
    fi
}

case "$type" in
    session)
        if confirm "Kill session '$session'?"; then
            # Check if it's a workspace session and cleanup
            local mode
            mode=$(tmux show-option -t "$session" -qv @tower_mode 2>/dev/null || echo "")
            if [[ "$mode" == "workspace" ]]; then
                cleanup_worktree "$session"
            fi

            tmux kill-session -t "$session"
            # Delete metadata file
            delete_metadata "$session"
            handle_info "Killed session: $session"
        fi
        ;;

    window)
        if confirm "Kill window '${session}:${window}'?"; then
            tmux kill-window -t "${session}:${window}"
            handle_info "Killed window: ${session}:${window}"
        fi
        ;;

    pane)
        if confirm "Kill pane '${session}:${window}.${pane}'?"; then
            tmux kill-pane -t "${session}:${window}.${pane}"
            handle_info "Killed pane"
        fi
        ;;

    *)
        handle_error "Unknown target type"
        ;;
esac
