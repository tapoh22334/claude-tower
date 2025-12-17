#!/usr/bin/env bash
# Main session picker with tree view and preview

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_DIR="$(dirname "$SCRIPT_DIR")"
TOWER_SCRIPT_NAME="tower.sh"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

debug_log "Starting tower.sh"

# Build tree structure
build_tree() {
    local active_session active_window active_pane
    active_session=$(tmux display-message -p '#S')
    active_window=$(tmux display-message -p '#I')
    active_pane=$(tmux display-message -p '#P')

    # Get all sessions
    tmux list-sessions -F '#{session_name}' 2>/dev/null | while read -r session; do
        local session_path session_type git_branch_display diff_stats

        # Get session's current path
        session_path=$(tmux display-message -t "$session" -p '#{pane_current_path}' 2>/dev/null || echo "")

        # Check if git repo
        if [[ -n "$session_path" ]] && git -C "$session_path" rev-parse --git-dir &>/dev/null; then
            session_type="W"  # Workspace
            local branch
            branch=$(git -C "$session_path" branch --show-current 2>/dev/null || echo "")
            local stats
            stats=$(git -C "$session_path" diff --numstat 2>/dev/null | awk '{add+=$1; del+=$2} END {if(add>0||del>0) printf "+%d,-%d", add, del}')
            git_branch_display="${ICON_GIT} ${branch}"
            [[ -n "$stats" ]] && diff_stats="$stats"
        else
            session_type="S"  # Simple
            git_branch_display="(no git)"
        fi

        # Session line
        local active_indicator=""
        [[ "$session" == "$active_session" ]] && active_indicator="${C_ACTIVE}${ICON_ACTIVE}${C_RESET} "

        printf "session:%s:%s %s[%s] %b%s%b  %b%s%b %b%s%b\n" \
            "$session" \
            "$ICON_SESSION" \
            "$active_indicator" \
            "$session_type" \
            "$C_SESSION" "$session" "$C_RESET" \
            "$C_GIT" "$git_branch_display" "$C_RESET" \
            "$C_DIFF_ADD" "$diff_stats" "$C_RESET"

        # Get windows for this session
        tmux list-windows -t "$session" -F '#{window_index}:#{window_name}:#{window_active}' 2>/dev/null | while read -r window_data; do
            local win_idx win_name win_active
            IFS=':' read -r win_idx win_name win_active <<< "$window_data"

            local window_active_indicator=""
            [[ "$session" == "$active_session" && "$win_idx" == "$active_window" ]] && window_active_indicator="${C_ACTIVE}${ICON_ACTIVE}${C_RESET}"

            printf "window:%s:%s:  ├─ %s %b%s: %s%b %s\n" \
                "$session" \
                "$win_idx" \
                "$ICON_WINDOW" \
                "$C_WINDOW" "$win_idx" "$win_name" "$C_RESET" \
                "$window_active_indicator"

            # Get panes for this window
            tmux list-panes -t "${session}:${win_idx}" -F '#{pane_index}:#{pane_current_command}:#{pane_active}' 2>/dev/null | while read -r pane_data; do
                local pane_idx pane_cmd pane_is_active
                IFS=':' read -r pane_idx pane_cmd pane_is_active <<< "$pane_data"

                local pane_active_indicator=""
                [[ "$session" == "$active_session" && "$win_idx" == "$active_window" && "$pane_idx" == "$active_pane" ]] && pane_active_indicator="${C_ACTIVE}${ICON_ACTIVE}${C_RESET}"

                printf "pane:%s:%s:%s:  │  └─ %s %b%s: %s%b %s\n" \
                    "$session" \
                    "$win_idx" \
                    "$pane_idx" \
                    "$ICON_PANE" \
                    "$C_PANE" "$pane_idx" "$pane_cmd" "$C_RESET" \
                    "$pane_active_indicator"
            done
        done
    done
}

# Parse selection and switch
handle_selection() {
    local selection="$1"
    local type selected_session selected_window selected_pane

    IFS=':' read -r type selected_session selected_window selected_pane _ <<< "$selection"

    case "$type" in
        session)
            tmux switch-client -t "$selected_session" || handle_error "Failed to switch to session"
            ;;
        window)
            tmux switch-client -t "${selected_session}:${selected_window}" || handle_error "Failed to switch to window"
            ;;
        pane)
            tmux switch-client -t "${selected_session}:${selected_window}.${selected_pane}" || handle_error "Failed to switch to pane"
            ;;
    esac
}

# Main
main() {
    # Check if fzf is available
    require_command fzf || exit 1

    # Build tree and show fzf picker
    local selection
    selection=$(build_tree | fzf-tmux -p 80%,70% \
        --ansi \
        --no-sort \
        --reverse \
        --header="Enter:select | n:new | r:rename | x:kill | D:diff | ?:help" \
        --preview="$SCRIPT_DIR/preview.sh {}" \
        --preview-window=right:50% \
        --bind="n:execute($SCRIPT_DIR/new-session.sh)+reload($SCRIPT_DIR/tower.sh --list)" \
        --bind="r:execute($SCRIPT_DIR/rename.sh {})+reload($SCRIPT_DIR/tower.sh --list)" \
        --bind="x:execute($SCRIPT_DIR/kill.sh {})+reload($SCRIPT_DIR/tower.sh --list)" \
        --bind="D:preview($SCRIPT_DIR/diff.sh {})" \
        --bind="?:preview($SCRIPT_DIR/help.sh)" \
        --delimiter=':' \
    ) || exit 0

    [[ -n "$selection" ]] && handle_selection "$selection"
}

# If called with --list, just output the tree (for reload)
if [[ "${1:-}" == "--list" ]]; then
    build_tree
else
    main
fi
