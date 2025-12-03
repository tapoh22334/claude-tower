#!/usr/bin/env bash
# Preview script for fzf - shows pane content or diff

set -e

# Parse input (format: type:session:window:pane:display_text)
INPUT="$1"
IFS=':' read -r type session window pane _ <<< "$INPUT"

# Colors
C_RESET="\033[0m"
C_HEADER="\033[1;36m"
C_INFO="\033[0;33m"
C_ADD="\033[0;32m"
C_DEL="\033[0;31m"
C_HUNK="\033[0;36m"

show_session_info() {
    local session="$1"

    # Get session info
    local created attached windows path
    created=$(tmux display-message -t "$session" -p '#{session_created}' 2>/dev/null || echo "")
    attached=$(tmux display-message -t "$session" -p '#{session_attached}' 2>/dev/null || echo "0")
    windows=$(tmux list-windows -t "$session" 2>/dev/null | wc -l)
    path=$(tmux display-message -t "$session" -p '#{pane_current_path}' 2>/dev/null || echo "")

    echo -e "${C_HEADER}━━━ Session: $session ━━━${C_RESET}"
    echo ""
    echo -e "${C_INFO}Path:${C_RESET} $path"
    echo -e "${C_INFO}Windows:${C_RESET} $windows"
    echo -e "${C_INFO}Attached:${C_RESET} $([ "$attached" -gt 0 ] && echo "Yes" || echo "No")"
    echo ""

    # Check if git repo and show diff summary
    if [[ -n "$path" ]] && git -C "$path" rev-parse --git-dir &>/dev/null 2>&1; then
        local branch=$(git -C "$path" branch --show-current 2>/dev/null)
        local status=$(git -C "$path" status --short 2>/dev/null | head -10)

        echo -e "${C_HEADER}━━━ Git Status ━━━${C_RESET}"
        echo -e "${C_INFO}Branch:${C_RESET} $branch"
        echo ""
        if [[ -n "$status" ]]; then
            echo "$status"
        else
            echo "(clean)"
        fi
        echo ""
    fi

    # Show first pane content
    echo -e "${C_HEADER}━━━ Active Pane ━━━${C_RESET}"
    tmux capture-pane -t "$session" -p -e 2>/dev/null | tail -30
}

show_window_info() {
    local session="$1"
    local window="$2"

    echo -e "${C_HEADER}━━━ Window: ${session}:${window} ━━━${C_RESET}"
    echo ""

    # Get window info
    local name panes layout
    name=$(tmux display-message -t "${session}:${window}" -p '#{window_name}' 2>/dev/null || echo "")
    panes=$(tmux list-panes -t "${session}:${window}" 2>/dev/null | wc -l)
    layout=$(tmux display-message -t "${session}:${window}" -p '#{window_layout}' 2>/dev/null | cut -c1-20)

    echo -e "${C_INFO}Name:${C_RESET} $name"
    echo -e "${C_INFO}Panes:${C_RESET} $panes"
    echo ""

    # Show pane content
    echo -e "${C_HEADER}━━━ Pane Content ━━━${C_RESET}"
    tmux capture-pane -t "${session}:${window}" -p -e 2>/dev/null | tail -30
}

show_pane_content() {
    local session="$1"
    local window="$2"
    local pane="$3"

    local target="${session}:${window}.${pane}"

    echo -e "${C_HEADER}━━━ Pane: ${target} ━━━${C_RESET}"
    echo ""

    # Get pane info
    local cmd path pid
    cmd=$(tmux display-message -t "$target" -p '#{pane_current_command}' 2>/dev/null || echo "")
    path=$(tmux display-message -t "$target" -p '#{pane_current_path}' 2>/dev/null || echo "")
    pid=$(tmux display-message -t "$target" -p '#{pane_pid}' 2>/dev/null || echo "")

    echo -e "${C_INFO}Command:${C_RESET} $cmd"
    echo -e "${C_INFO}Path:${C_RESET} $path"
    echo -e "${C_INFO}PID:${C_RESET} $pid"
    echo ""

    # Show pane content
    echo -e "${C_HEADER}━━━ Content ━━━${C_RESET}"
    tmux capture-pane -t "$target" -p -e 2>/dev/null | tail -35
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
