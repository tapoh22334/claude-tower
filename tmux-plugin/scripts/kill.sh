#!/usr/bin/env bash
# Kill session, window, or pane

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="kill.sh"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

INPUT="$1"

if [[ -z "$INPUT" ]]; then
    handle_error "No input provided"
    exit 1
fi

IFS=':' read -r type selected_session selected_window selected_pane _ <<<"$INPUT"

debug_log "Kill request: type=$type, session=$selected_session, window=$selected_window, pane=$selected_pane"

remove_session_worktree() {
    local session_id="$1"

    debug_log "Removing worktree for session: $session_id"

    # Get stored repository path
    local repository_path
    repository_path=$(tmux show-option -t "$session_id" -qv @tower_repository 2>/dev/null || echo "")

    if [[ -n "$repository_path" ]]; then
        # Extract name from session (remove tower_ prefix)
        local name="${session_id#tower_}"
        local worktree_path="${TOWER_WORKTREE_DIR}/${name}"

        debug_log "Worktree path: $worktree_path, Repository: $repository_path"

        if [[ -d "$worktree_path" ]]; then
            # Validate path before removal
            if validate_path_within "$worktree_path" "$TOWER_WORKTREE_DIR"; then
                # Remove worktree
                local git_output
                if git_output=$(git -C "$repository_path" worktree remove "$worktree_path" 2>&1); then
                    handle_success "Removed worktree: $worktree_path"
                else
                    debug_log "Normal worktree removal failed: $git_output"
                    # Force remove if normal removal fails
                    if git_output=$(git -C "$repository_path" worktree remove --force "$worktree_path" 2>&1); then
                        handle_warning "Force removed worktree: $worktree_path"
                    else
                        handle_error "Failed to remove worktree: $git_output"
                    fi
                fi
            else
                handle_error "Invalid worktree path: path traversal detected, skipping cleanup"
            fi
        else
            debug_log "Worktree directory does not exist: $worktree_path"
        fi
    else
        debug_log "No repository path found for session: $session_id"
    fi
}

case "$type" in
    session)
        if [[ -z "$selected_session" ]]; then
            handle_error "No session specified"
            exit 1
        fi

        if confirm "Kill session '$selected_session'?"; then
            debug_log "Killing session: $selected_session"

            # Check if it's a workspace session type and cleanup
            session_type=$(tmux show-option -t "$selected_session" -qv @tower_session_type 2>/dev/null || echo "")
            if [[ "$session_type" == "workspace" ]]; then
                remove_session_worktree "$selected_session"
            fi

            if ! tmux kill-session -t "$selected_session" 2>/dev/null; then
                handle_error "Failed to kill session: $selected_session"
                exit 1
            fi

            # Delete metadata file
            delete_metadata "$selected_session"
            handle_success "Killed session: $selected_session"
        else
            debug_log "Kill cancelled by user"
        fi
        ;;

    window)
        if [[ -z "$selected_session" ]] || [[ -z "$selected_window" ]]; then
            handle_error "No window specified"
            exit 1
        fi

        if confirm "Kill window '${selected_session}:${selected_window}'?"; then
            debug_log "Killing window: ${selected_session}:${selected_window}"

            if ! tmux kill-window -t "${selected_session}:${selected_window}" 2>/dev/null; then
                handle_error "Failed to kill window: ${selected_session}:${selected_window}"
                exit 1
            fi

            handle_success "Killed window: ${selected_session}:${selected_window}"
        else
            debug_log "Kill cancelled by user"
        fi
        ;;

    pane)
        if [[ -z "$selected_session" ]] || [[ -z "$selected_window" ]] || [[ -z "$selected_pane" ]]; then
            handle_error "No pane specified"
            exit 1
        fi

        if confirm "Kill pane '${selected_session}:${selected_window}.${selected_pane}'?"; then
            debug_log "Killing pane: ${selected_session}:${selected_window}.${selected_pane}"

            if ! tmux kill-pane -t "${selected_session}:${selected_window}.${selected_pane}" 2>/dev/null; then
                handle_error "Failed to kill pane: ${selected_session}:${selected_window}.${selected_pane}"
                exit 1
            fi

            handle_success "Killed pane: ${selected_session}:${selected_window}.${selected_pane}"
        else
            debug_log "Kill cancelled by user"
        fi
        ;;

    *)
        handle_error "Unknown selection type: '$type'"
        exit 1
        ;;
esac
