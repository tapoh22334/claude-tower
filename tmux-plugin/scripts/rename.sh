#!/usr/bin/env bash
# Rename session or window

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

INPUT="$1"
IFS=':' read -r type selected_session selected_window selected_pane _ <<< "$INPUT"

rename_session() {
    local session="$1"

    # Get new name
    local new_name
    new_name=$(echo "" | fzf-tmux -p 50%,20% \
        --print-query \
        --prompt="New name for session '$session': " \
        --bind="enter:accept-or-print-query" \
    | head -1) || exit 0

    if [[ -n "$new_name" ]]; then
        # Sanitize the new name
        local sanitized_name
        sanitized_name=$(sanitize_name "$new_name")
        if [[ -z "$sanitized_name" ]]; then
            handle_error "Invalid session name"
            exit 1
        fi
        tmux rename-session -t "$session" "$sanitized_name"
        handle_info "Renamed session to: $sanitized_name"
    fi
}

rename_window() {
    local session="$1"
    local window="$2"

    # Get new name
    local current_window_name
    current_window_name=$(tmux display-message -t "${session}:${window}" -p '#{window_name}')
    local new_name
    new_name=$(echo "" | fzf-tmux -p 50%,20% \
        --print-query \
        --prompt="New name for window '$current_window_name': " \
        --bind="enter:accept-or-print-query" \
    | head -1) || exit 0

    if [[ -n "$new_name" ]]; then
        tmux rename-window -t "${session}:${window}" "$new_name"
        handle_info "Renamed window to: $new_name"
    fi
}

case "$type" in
    session)
        rename_session "$selected_session"
        ;;

    window)
        rename_window "$selected_session" "$selected_window"
        ;;

    *)
        handle_error "Can only rename sessions and windows"
        ;;
esac
