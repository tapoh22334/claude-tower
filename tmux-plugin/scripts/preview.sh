#!/usr/bin/env bash
# Preview script for fzf - shows pane content or diff

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Parse input (format: type:session:window:pane:display_text)
INPUT="$1"
IFS=':' read -r type selected_session selected_window selected_pane _ <<< "$INPUT"

show_session_details() {
    local session="$1"

    # Get session details
    local created_time is_attached window_count session_path
    created_time=$(tmux display-message -t "$session" -p '#{session_created}' 2>/dev/null || echo "")
    is_attached=$(tmux display-message -t "$session" -p '#{session_attached}' 2>/dev/null || echo "0")
    window_count=$(tmux list-windows -t "$session" 2>/dev/null | wc -l)
    session_path=$(tmux display-message -t "$session" -p '#{pane_current_path}' 2>/dev/null || echo "")

    printf "%b━━━ Session: %s ━━━%b\n" "$C_HEADER" "$session" "$C_RESET"
    echo ""
    printf "%bPath:%b %s\n" "$C_INFO" "$C_RESET" "$session_path"
    printf "%bWindows:%b %s\n" "$C_INFO" "$C_RESET" "$window_count"
    printf "%bAttached:%b %s\n" "$C_INFO" "$C_RESET" "$([ "$is_attached" -gt 0 ] && echo "Yes" || echo "No")"
    echo ""

    # Check if git repo and show diff summary
    if [[ -n "$session_path" ]] && git -C "$session_path" rev-parse --git-dir &>/dev/null; then
        local branch
        branch=$(git -C "$session_path" branch --show-current 2>/dev/null)
        local git_status
        git_status=$(git -C "$session_path" status --short 2>/dev/null | head -10)

        printf "%b━━━ Git Status ━━━%b\n" "$C_HEADER" "$C_RESET"
        printf "%bBranch:%b %s\n" "$C_INFO" "$C_RESET" "$branch"
        echo ""
        if [[ -n "$git_status" ]]; then
            echo "$git_status"
        else
            echo "(clean)"
        fi
        echo ""
    fi

    # Show first pane content (capture scrollback with -S -)
    printf "%b━━━ Active Pane ━━━%b\n" "$C_HEADER" "$C_RESET"
    tmux capture-pane -t "$session" -p -e -S - 2>/dev/null | tail -"$PREVIEW_LINES"
}

show_window_details() {
    local session="$1"
    local window="$2"

    printf "%b━━━ Window: %s:%s ━━━%b\n" "$C_HEADER" "$session" "$window" "$C_RESET"
    echo ""

    # Get window details
    local window_name pane_count window_layout
    window_name=$(tmux display-message -t "${session}:${window}" -p '#{window_name}' 2>/dev/null || echo "")
    pane_count=$(tmux list-panes -t "${session}:${window}" 2>/dev/null | wc -l)
    window_layout=$(tmux display-message -t "${session}:${window}" -p '#{window_layout}' 2>/dev/null | cut -c1-20)

    printf "%bName:%b %s\n" "$C_INFO" "$C_RESET" "$window_name"
    printf "%bPanes:%b %s\n" "$C_INFO" "$C_RESET" "$pane_count"
    echo ""

    # Show pane content (capture scrollback with -S -)
    printf "%b━━━ Pane Content ━━━%b\n" "$C_HEADER" "$C_RESET"
    tmux capture-pane -t "${session}:${window}" -p -e -S - 2>/dev/null | tail -"$PREVIEW_LINES"
}

show_pane_details() {
    local session="$1"
    local window="$2"
    local pane="$3"

    local pane_target="${session}:${window}.${pane}"

    printf "%b━━━ Pane: %s ━━━%b\n" "$C_HEADER" "$pane_target" "$C_RESET"
    echo ""

    # Get pane details
    local pane_command pane_path pane_pid
    pane_command=$(tmux display-message -t "$pane_target" -p '#{pane_current_command}' 2>/dev/null || echo "")
    pane_path=$(tmux display-message -t "$pane_target" -p '#{pane_current_path}' 2>/dev/null || echo "")
    pane_pid=$(tmux display-message -t "$pane_target" -p '#{pane_pid}' 2>/dev/null || echo "")

    printf "%bCommand:%b %s\n" "$C_INFO" "$C_RESET" "$pane_command"
    printf "%bPath:%b %s\n" "$C_INFO" "$C_RESET" "$pane_path"
    printf "%bPID:%b %s\n" "$C_INFO" "$C_RESET" "$pane_pid"
    echo ""

    # Show pane content (capture scrollback with -S -)
    printf "%b━━━ Content ━━━%b\n" "$C_HEADER" "$C_RESET"
    tmux capture-pane -t "$pane_target" -p -e -S - 2>/dev/null | tail -"$PREVIEW_LINES"
}

# Main
case "$type" in
    session)
        show_session_details "$selected_session"
        ;;
    window)
        show_window_details "$selected_session" "$selected_window"
        ;;
    pane)
        show_pane_details "$selected_session" "$selected_window" "$selected_pane"
        ;;
    *)
        echo "Unknown type: $type"
        ;;
esac
