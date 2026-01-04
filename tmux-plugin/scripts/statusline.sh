#!/usr/bin/env bash
# Statusline - Generate status bar content for tmux
# Used by: set -g status-right '#(~/.tmux/plugins/claude-tower/tmux-plugin/scripts/statusline.sh)'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library (quietly, statusline runs frequently)
source "$SCRIPT_DIR/../lib/common.sh" 2>/dev/null || {
    # Fallback colors if common.sh fails
    C_RESET="\033[0m"
    C_GREEN="\033[0;32m"
    C_YELLOW="\033[0;33m"
    C_BLUE="\033[0;34m"
    C_RED="\033[0;31m"
}

# Get current session info
get_session_info() {
    local session
    session=$(tmux display-message -p '#S' 2>/dev/null)

    if [[ -z "$session" ]]; then
        echo ""
        return
    fi

    local session_type="S"
    local git_info=""
    local worktree_info=""

    # Check if tower session
    if [[ "$session" == tower_* ]]; then
        if load_metadata "$session" 2>/dev/null; then
            if [[ "$META_SESSION_TYPE" == "workspace" ]]; then
                session_type="W"

                # Get git info from worktree
                if [[ -n "$META_WORKTREE_PATH" && -d "$META_WORKTREE_PATH" ]]; then
                    local branch
                    branch=$(git -C "$META_WORKTREE_PATH" branch --show-current 2>/dev/null)

                    local status_counts
                    status_counts=$(git -C "$META_WORKTREE_PATH" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

                    if [[ "$status_counts" -gt 0 ]]; then
                        git_info="#[fg=yellow]⎇ ${branch}*#[default]"
                    else
                        git_info="#[fg=green]⎇ ${branch}#[default]"
                    fi

                    # Source commit info
                    if [[ -n "$META_SOURCE_COMMIT" ]]; then
                        local short_commit="${META_SOURCE_COMMIT:0:7}"
                        worktree_info="#[fg=cyan]@${short_commit}#[default]"
                    fi
                fi
            fi
        fi
    else
        # Non-tower session - check current path for git
        local pane_path
        pane_path=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null)

        if [[ -n "$pane_path" ]] && git -C "$pane_path" rev-parse --git-dir &>/dev/null; then
            session_type="G"
            local branch
            branch=$(git -C "$pane_path" branch --show-current 2>/dev/null)

            local status_counts
            status_counts=$(git -C "$pane_path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

            if [[ "$status_counts" -gt 0 ]]; then
                git_info="#[fg=yellow]⎇ ${branch}*#[default]"
            else
                git_info="#[fg=green]⎇ ${branch}#[default]"
            fi
        fi
    fi

    # Format output
    local display_name="${session#tower_}"
    display_name="${display_name:0:20}"

    echo "#[fg=blue][${session_type}]#[default] ${display_name} ${git_info} ${worktree_info}"
}

# Get workspace statistics
get_workspace_stats() {
    local total_sessions workspace_count simple_count

    total_sessions=$(tmux list-sessions 2>/dev/null | wc -l | tr -d ' ')
    workspace_count=0
    simple_count=0

    for meta_file in "${TOWER_METADATA_DIR:-$HOME/.claude-tower/metadata}"/*.meta; do
        if [[ -f "$meta_file" ]]; then
            local session_id
            session_id=$(basename "$meta_file" .meta)
            if tmux has-session -t "$session_id" 2>/dev/null; then
                if grep -q "session_type=workspace" "$meta_file" 2>/dev/null; then
                    ((workspace_count++)) || true
                else
                    ((simple_count++)) || true
                fi
            fi
        fi
    done

    echo "#[fg=cyan]📁${workspace_count}W/${simple_count}S#[default]"
}

# Main output
main() {
    local mode="${1:-full}"

    case "$mode" in
        session)
            get_session_info
            ;;
        stats)
            get_workspace_stats
            ;;
        full | *)
            echo "$(get_session_info) │ $(get_workspace_stats)"
            ;;
    esac
}

main "$@"
