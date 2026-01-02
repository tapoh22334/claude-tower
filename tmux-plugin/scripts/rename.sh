#!/usr/bin/env bash
# Rename session or window

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="rename.sh"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

INPUT="$1"

if [[ -z "$INPUT" ]]; then
    handle_error "No input provided"
    exit 1
fi

IFS=':' read -r type selected_session selected_window selected_pane _ <<<"$INPUT"

debug_log "Rename request: type=$type, session=$selected_session, window=$selected_window"

rename_session() {
    local session="$1"

    if [[ -z "$session" ]]; then
        handle_error "No session specified"
        return 1
    fi

    debug_log "Renaming session: $session"

    # Get new name
    local new_name
    new_name=$(echo "" | fzf-tmux -p 50%,20% \
        --print-query \
        --prompt="New name for session '$session': " \
        --bind="enter:accept-or-print-query" |
        head -1) || {
        debug_log "Rename cancelled by user"
        exit 0
    }

    if [[ -n "$new_name" ]]; then
        # Sanitize the new name
        local sanitized_name
        sanitized_name=$(sanitize_name "$new_name")
        if [[ -z "$sanitized_name" ]]; then
            handle_error "Invalid session name: contains only invalid characters"
            exit 1
        fi

        if ! validate_session_name "$sanitized_name"; then
            handle_error "Invalid session name format"
            exit 1
        fi

        if ! tmux rename-session -t "$session" "$sanitized_name" 2>/dev/null; then
            handle_error "Failed to rename session"
            exit 1
        fi

        handle_success "Renamed session to: $sanitized_name"
    else
        debug_log "Empty name provided, skipping rename"
    fi
}

rename_window() {
    local session="$1"
    local window="$2"

    if [[ -z "$session" ]] || [[ -z "$window" ]]; then
        handle_error "No window specified"
        return 1
    fi

    debug_log "Renaming window: ${session}:${window}"

    # Get new name
    local current_window_name
    current_window_name=$(tmux display-message -t "${session}:${window}" -p '#{window_name}' 2>/dev/null)
    if [[ -z "$current_window_name" ]]; then
        handle_error "Window not found: ${session}:${window}"
        return 1
    fi

    local new_name
    new_name=$(echo "" | fzf-tmux -p 50%,20% \
        --print-query \
        --prompt="New name for window '$current_window_name': " \
        --bind="enter:accept-or-print-query" |
        head -1) || {
        debug_log "Rename cancelled by user"
        exit 0
    }

    if [[ -n "$new_name" ]]; then
        if ! tmux rename-window -t "${session}:${window}" "$new_name" 2>/dev/null; then
            handle_error "Failed to rename window"
            exit 1
        fi

        handle_success "Renamed window to: $new_name"
    else
        debug_log "Empty name provided, skipping rename"
    fi
}

case "$type" in
    session)
        rename_session "$selected_session"
        ;;

    window)
        rename_window "$selected_session" "$selected_window"
        ;;

    pane)
        handle_warning "Panes cannot be renamed"
        ;;

    *)
        handle_error "Unknown selection type: '$type'"
        exit 1
        ;;
esac
