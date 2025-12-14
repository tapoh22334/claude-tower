#!/usr/bin/env bash
# Preview script for fzf - shows pane content or diff

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Parse input (format: type:session:window:pane:display_text)
INPUT="$1"
IFS=':' read -r type session window pane _ <<< "$INPUT"

show_session_info() {
    local session="$1"

    # Get session info
    local created attached windows path
    created=$(tmux display-message -t "$session" -p '#{session_created}' 2>/dev/null || echo "")
    attached=$(tmux display-message -t "$session" -p '#{session_attached}' 2>/dev/null || echo "0")
    windows=$(tmux list-windows -t "$session" 2>/dev/null | wc -l)
    path=$(tmux display-message -t "$session" -p '#{pane_current_path}' 2>/dev/null || echo "")

    printf "%b━━━ Session: %s ━━━%b\n" "$C_HEADER" "$session" "$C_RESET"
    echo ""
    printf "%bPath:%b %s\n" "$C_INFO" "$C_RESET" "$path"
    printf "%bWindows:%b %s\n" "$C_INFO" "$C_RESET" "$windows"
    printf "%bAttached:%b %s\n" "$C_INFO" "$C_RESET" "$([ "$attached" -gt 0 ] && echo "Yes" || echo "No")"
    echo ""

    # Check if git repo and show diff summary
    if [[ -n "$path" ]] && git -C "$path" rev-parse --git-dir &>/dev/null; then
        local branch
        branch=$(git -C "$path" branch --show-current 2>/dev/null)
        local status
        status=$(git -C "$path" status --short 2>/dev/null | head -10)

        printf "%b━━━ Git Status ━━━%b\n" "$C_HEADER" "$C_RESET"
        printf "%bBranch:%b %s\n" "$C_INFO" "$C_RESET" "$branch"
        echo ""
        if [[ -n "$status" ]]; then
            echo "$status"
        else
            echo "(clean)"
        fi
        echo ""
    fi

    # Show first pane content
    printf "%b━━━ Active Pane ━━━%b\n" "$C_HEADER" "$C_RESET"
    tmux capture-pane -t "$session" -p -e 2>/dev/null | tail -"$PREVIEW_LINES"
}

show_window_info() {
    local session="$1"
    local window="$2"

    printf "%b━━━ Window: %s:%s ━━━%b\n" "$C_HEADER" "$session" "$window" "$C_RESET"
    echo ""

    # Get window info
    local name panes layout
    name=$(tmux display-message -t "${session}:${window}" -p '#{window_name}' 2>/dev/null || echo "")
    panes=$(tmux list-panes -t "${session}:${window}" 2>/dev/null | wc -l)
    layout=$(tmux display-message -t "${session}:${window}" -p '#{window_layout}' 2>/dev/null | cut -c1-20)

    printf "%bName:%b %s\n" "$C_INFO" "$C_RESET" "$name"
    printf "%bPanes:%b %s\n" "$C_INFO" "$C_RESET" "$panes"
    echo ""

    # Show pane content
    printf "%b━━━ Pane Content ━━━%b\n" "$C_HEADER" "$C_RESET"
    tmux capture-pane -t "${session}:${window}" -p -e 2>/dev/null | tail -"$PREVIEW_LINES"
}

show_pane_content() {
    local session="$1"
    local window="$2"
    local pane="$3"

    local target="${session}:${window}.${pane}"

    printf "%b━━━ Pane: %s ━━━%b\n" "$C_HEADER" "$target" "$C_RESET"
    echo ""

    # Get pane info
    local cmd path pid
    cmd=$(tmux display-message -t "$target" -p '#{pane_current_command}' 2>/dev/null || echo "")
    path=$(tmux display-message -t "$target" -p '#{pane_current_path}' 2>/dev/null || echo "")
    pid=$(tmux display-message -t "$target" -p '#{pane_pid}' 2>/dev/null || echo "")

    printf "%bCommand:%b %s\n" "$C_INFO" "$C_RESET" "$cmd"
    printf "%bPath:%b %s\n" "$C_INFO" "$C_RESET" "$path"
    printf "%bPID:%b %s\n" "$C_INFO" "$C_RESET" "$pid"
    echo ""

    # Show pane content
    printf "%b━━━ Content ━━━%b\n" "$C_HEADER" "$C_RESET"
    tmux capture-pane -t "$target" -p -e 2>/dev/null | tail -"$PREVIEW_LINES"
}

# Main
case "$type" in
    session)
        show_session_info "$session"
        ;;
    window)
        show_window_info "$session" "$window"
        ;;
    pane)
        show_pane_content "$session" "$window" "$pane"
        ;;
    *)
        echo "Unknown type: $type"
        ;;
esac
