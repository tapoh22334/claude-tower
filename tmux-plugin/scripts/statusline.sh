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
    # `|| session=""` absorbs the non-zero exit when there is no tmux server
    # so common.sh's `set -e` doesn't kill the statusline mid-render.
    session=$(tmux display-message -p '#S' 2>/dev/null) || session=""

    if [[ -z "$session" ]]; then
        echo ""
        return
    fi

    local session_type="S"
    local git_info=""

    # Determine the directory to inspect for git info.
    # Tower sessions use their recorded directory_path; other sessions use pane_current_path.
    local target_path=""
    if [[ "$session" == tower_* ]]; then
        session_type="T"
        if load_metadata "$session" 2>/dev/null; then
            target_path="$META_DIRECTORY_PATH"
        fi
    else
        target_path=$(tmux display-message -p '#{pane_current_path}' 2>/dev/null) || target_path=""
    fi

    if [[ -n "$target_path" ]] && git -C "$target_path" rev-parse --git-dir &>/dev/null; then
        [[ "$session_type" == "S" ]] && session_type="G"
        local branch
        branch=$(git -C "$target_path" branch --show-current 2>/dev/null)

        local status_counts
        status_counts=$(git -C "$target_path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

        if [[ "$status_counts" -gt 0 ]]; then
            git_info="#[fg=yellow]⎇ ${branch}*#[default]"
        else
            git_info="#[fg=green]⎇ ${branch}#[default]"
        fi
    fi

    # Format output
    local display_name="${session#tower_}"
    display_name="${display_name:0:20}"

    echo "#[fg=blue][${session_type}]#[default] ${display_name} ${git_info}"
}

# Get session counts: active (tmux session exists) and dormant (metadata only)
get_session_stats() {
    local active_count=0
    local dormant_count=0

    for meta_file in "${TOWER_METADATA_DIR:-$HOME/.claude-tower/metadata}"/*.meta; do
        if [[ -f "$meta_file" ]]; then
            local session_id
            session_id=$(basename "$meta_file" .meta)
            if tmux has-session -t "$session_id" 2>/dev/null; then
                ((active_count++)) || true
            else
                ((dormant_count++)) || true
            fi
        fi
    done

    echo "#[fg=cyan]📁${active_count}▶/${dormant_count}○#[default]"
}

# Main output
main() {
    local mode="${1:-full}"

    case "$mode" in
        session)
            get_session_info
            ;;
        stats)
            get_session_stats
            ;;
        full | *)
            echo "$(get_session_info) │ $(get_session_stats)"
            ;;
    esac
}

main "$@"
