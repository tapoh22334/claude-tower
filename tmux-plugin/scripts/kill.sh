#!/usr/bin/env bash
# Kill session, window, or pane

set -e

PILOT_WORKTREE_DIR="${TMUX_PILOT_WORKTREE_DIR:-$HOME/.tmux-pilot/worktrees}"

INPUT="$1"
IFS=':' read -r type session window pane _ <<< "$INPUT"

confirm() {
    local msg="$1"
    local result
    result=$(echo -e "Yes\nNo" | fzf-tmux -p 40%,20% \
        --header="$msg" \
        --no-info \
    ) || echo "No"
    [[ "$result" == "Yes" ]]
}

cleanup_worktree() {
    local session_name="$1"

    # Get stored repo path
    local repo_path
    repo_path=$(tmux show-option -t "$session_name" -qv @pilot_repo 2>/dev/null || echo "")

    if [[ -n "$repo_path" ]]; then
        # Extract name from session (remove pilot_ prefix)
        local name="${session_name#pilot_}"
        local worktree_path="${PILOT_WORKTREE_DIR}/${name}"

        if [[ -d "$worktree_path" ]]; then
            # Remove worktree
            git -C "$repo_path" worktree remove --force "$worktree_path" 2>/dev/null || true
            tmux display-message "Cleaned up worktree: $worktree_path"
        fi
    fi
}

case "$type" in
    session)
        if confirm "Kill session '$session'?"; then
            # Check if it's a workspace session and cleanup
            local mode
            mode=$(tmux show-option -t "$session" -qv @pilot_mode 2>/dev/null || echo "")
            if [[ "$mode" == "workspace" ]]; then
                cleanup_worktree "$session"
            fi

            tmux kill-session -t "$session"
            tmux display-message "Killed session: $session"
        fi
        ;;

    window)
        if confirm "Kill window '${session}:${window}'?"; then
            tmux kill-window -t "${session}:${window}"
            tmux display-message "Killed window: ${session}:${window}"
        fi
        ;;

    pane)
        if confirm "Kill pane '${session}:${window}.${pane}'?"; then
            tmux kill-pane -t "${session}:${window}.${pane}"
            tmux display-message "Killed pane"
        fi
        ;;

    *)
        tmux display-message "Unknown target type"
        ;;
esac
