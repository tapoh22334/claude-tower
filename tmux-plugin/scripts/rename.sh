#!/usr/bin/env bash
# Rename session or window

set -e

INPUT="$1"
IFS=':' read -r type session window pane _ <<< "$INPUT"

case "$type" in
    session)
        # Get new name
        new_name=$(echo "" | fzf-tmux -p 50%,20% \
            --print-query \
            --prompt="New name for session '$session': " \
            --bind="enter:accept-or-print-query" \
        | head -1) || exit 0

        if [[ -n "$new_name" ]]; then
            tmux rename-session -t "$session" "$new_name"
            tmux display-message "Renamed session to: $new_name"
        fi
        ;;

    window)
        # Get new name
        current_name=$(tmux display-message -t "${session}:${window}" -p '#{window_name}')
        new_name=$(echo "" | fzf-tmux -p 50%,20% \
            --print-query \
            --prompt="New name for window '$current_name': " \
            --bind="enter:accept-or-print-query" \
        | head -1) || exit 0

        if [[ -n "$new_name" ]]; then
            tmux rename-window -t "${session}:${window}" "$new_name"
            tmux display-message "Renamed window to: $new_name"
        fi
        ;;

    *)
        tmux display-message "Can only rename sessions and windows"
        ;;
esac
