#!/usr/bin/env bash
# Sidebar - Minimal left panel for session overview
# Toggle with prefix + C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="sidebar.sh"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Sidebar configuration
readonly SIDEBAR_WIDTH="${CLAUDE_TOWER_SIDEBAR_WIDTH:-24}"
readonly SIDEBAR_PANE_NAME="tower_sidebar"

# Icons for compact display
readonly ICON_WORKSPACE="W"
readonly ICON_SIMPLE="S"
readonly ICON_CURRENT="▶"
readonly ICON_CHANGED="*"

# Check if sidebar is open
is_sidebar_open() {
    local current_window
    current_window=$(tmux display-message -p '#{window_id}')
    tmux list-panes -t "$current_window" -F '#{pane_title}' 2>/dev/null | grep -q "^${SIDEBAR_PANE_NAME}$"
}

# Get sidebar pane ID
get_sidebar_pane_id() {
    local current_window
    current_window=$(tmux display-message -p '#{window_id}')
    tmux list-panes -t "$current_window" -F '#{pane_id}:#{pane_title}' 2>/dev/null | \
        grep ":${SIDEBAR_PANE_NAME}$" | cut -d: -f1
}

# Build compact session list for sidebar
build_sidebar_content() {
    local active_session
    active_session=$(tmux display-message -p '#S')

    echo -e "${C_HEADER}┌─ Sessions ────────┐${C_RESET}"

    # Get all sessions
    tmux list-sessions -F '#{session_name}' 2>/dev/null | while read -r session; do
        local session_path session_type indicator branch_info
        local is_current=""

        # Get session's current path
        session_path=$(tmux display-message -t "$session" -p '#{pane_current_path}' 2>/dev/null || echo "")

        # Check if tower_ session and load metadata
        if [[ "$session" == tower_* ]]; then
            if load_metadata "$session"; then
                session_type="$META_SESSION_TYPE"
            else
                session_type="simple"
            fi
        else
            # Non-tower session - check if git repo
            if [[ -n "$session_path" ]] && git -C "$session_path" rev-parse --git-dir &>/dev/null; then
                session_type="workspace"
            else
                session_type="simple"
            fi
        fi

        # Type indicator
        if [[ "$session_type" == "workspace" ]]; then
            indicator="$ICON_WORKSPACE"
        else
            indicator="$ICON_SIMPLE"
        fi

        # Current session marker
        if [[ "$session" == "$active_session" ]]; then
            is_current="${C_ACTIVE}${ICON_CURRENT}${C_RESET}"
        else
            is_current=" "
        fi

        # Git branch (truncated)
        if [[ "$session_type" == "workspace" && -n "$session_path" ]]; then
            local branch
            branch=$(git -C "$session_path" branch --show-current 2>/dev/null | cut -c1-10)
            local has_changes=""
            if [[ -n $(git -C "$session_path" status --porcelain 2>/dev/null) ]]; then
                has_changes="${C_YELLOW}${ICON_CHANGED}${C_RESET}"
            fi
            branch_info=" ${C_GIT}${branch}${C_RESET}${has_changes}"
        else
            branch_info=""
        fi

        # Display name (truncated)
        local display_name="${session#tower_}"
        display_name="${display_name:0:12}"

        printf "│%s[%s]%b%-12s%b%s│\n" \
            "$is_current" \
            "$indicator" \
            "$C_SESSION" \
            "$display_name" \
            "$C_RESET" \
            "$branch_info"
    done

    echo -e "${C_HEADER}├──────────────────┤${C_RESET}"
    echo -e "│ ${C_INFO}n${C_RESET}:new ${C_INFO}?${C_RESET}:detail   │"
    echo -e "${C_HEADER}└──────────────────┘${C_RESET}"
}

# Create sidebar pane
create_sidebar() {
    local current_pane
    current_pane=$(tmux display-message -p '#{pane_id}')

    # Split window to left, create sidebar
    tmux split-window -hbdl "$SIDEBAR_WIDTH" \
        "printf '\\033]2;${SIDEBAR_PANE_NAME}\\033\\\\'; $SCRIPT_DIR/sidebar.sh --render"

    # Return focus to original pane
    tmux select-pane -t "$current_pane"
}

# Close sidebar
close_sidebar() {
    local sidebar_pane
    sidebar_pane=$(get_sidebar_pane_id)
    if [[ -n "$sidebar_pane" ]]; then
        tmux kill-pane -t "$sidebar_pane"
    fi
}

# Render sidebar content (called from within sidebar pane)
render_sidebar() {
    # Set pane title
    printf '\033]2;%s\033\\' "$SIDEBAR_PANE_NAME"

    # Clear and render
    clear

    while true; do
        # Move cursor to top
        printf '\033[H'

        # Build and display content
        build_sidebar_content

        # Wait for input or refresh
        if read -rsn1 -t 2 key; then
            case "$key" in
                n)
                    # Launch new session dialog in main pane
                    tmux run-shell -t ":.!" "$SCRIPT_DIR/new-session.sh"
                    ;;
                "?")
                    # Open full tree view overlay
                    tmux run-shell -t ":.!" "$SCRIPT_DIR/tower.sh"
                    ;;
                j|"$(printf '\e[B')")
                    # Navigate down (future: select session)
                    ;;
                k|"$(printf '\e[A')")
                    # Navigate up (future: select session)
                    ;;
                "$(printf '\e')")  # Escape
                    exit 0
                    ;;
                q)
                    exit 0
                    ;;
            esac
        fi
    done
}

# Toggle sidebar
toggle_sidebar() {
    if is_sidebar_open; then
        close_sidebar
    else
        create_sidebar
    fi
}

# Main entry point
case "${1:-}" in
    --render)
        render_sidebar
        ;;
    --open)
        if ! is_sidebar_open; then
            create_sidebar
        fi
        ;;
    --close)
        close_sidebar
        ;;
    --toggle|*)
        toggle_sidebar
        ;;
esac
