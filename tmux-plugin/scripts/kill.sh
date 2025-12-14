#!/usr/bin/env bash
# Kill session, window, or pane

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

INPUT="$1"
IFS=':' read -r type selected_session selected_window selected_pane _ <<< "$INPUT"

remove_session_worktree() {
    local session_id="$1"

    # Get stored repository path
    local repository_path
    repository_path=$(tmux show-option -t "$session_id" -qv @tower_repository 2>/dev/null || echo "")

    if [[ -n "$repository_path" ]]; then
        # Extract name from session (remove tower_ prefix)
        local name="${session_id#tower_}"
        local worktree_path="${TOWER_WORKTREE_DIR}/${name}"

        if [[ -d "$worktree_path" ]]; then
            # Validate path before removal
            if validate_path_within "$worktree_path" "$TOWER_WORKTREE_DIR"; then
                # Remove worktree
                if git -C "$repository_path" worktree remove "$worktree_path" 2>/dev/null; then
                    handle_info "Removed worktree: $worktree_path"
                else
                    # Force remove if normal removal fails
                    git -C "$repository_path" worktree remove --force "$worktree_path" 2>/dev/null || true
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
        if confirm "Kill session '$selected_session'?"; then
            # Check if it's a workspace session type and cleanup
            local session_type
            session_type=$(tmux show-option -t "$selected_session" -qv @tower_session_type 2>/dev/null || echo "")
            if [[ "$session_type" == "workspace" ]]; then
                remove_session_worktree "$selected_session"
            fi

            tmux kill-session -t "$selected_session"
            # Delete metadata file
            delete_metadata "$selected_session"
            handle_info "Killed session: $selected_session"
        fi
        ;;

    window)
        if confirm "Kill window '${selected_session}:${selected_window}'?"; then
            tmux kill-window -t "${selected_session}:${selected_window}"
            handle_info "Killed window: ${selected_session}:${selected_window}"
        fi
        ;;

    pane)
        if confirm "Kill pane '${selected_session}:${selected_window}.${selected_pane}'?"; then
            tmux kill-pane -t "${selected_session}:${selected_window}.${selected_pane}"
            handle_info "Killed pane"
        fi
        ;;

    *)
        handle_error "Unknown selection type"
        ;;
esac
