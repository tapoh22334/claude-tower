#!/usr/bin/env bash
# Main session picker with tree view and preview

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PILOT_DIR="$(dirname "$SCRIPT_DIR")"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Build tree structure
build_tree() {
    local current_session current_window current_pane
    current_session=$(tmux display-message -p '#S')
    current_window=$(tmux display-message -p '#I')
    current_pane=$(tmux display-message -p '#P')

    # Get all sessions
    tmux list-sessions -F '#{session_name}' 2>/dev/null | while read -r session; do
        local session_path session_mode git_info diff_info

        # Get session's current path
        session_path=$(tmux display-message -t "$session" -p '#{pane_current_path}' 2>/dev/null || echo "")

        # Check if git repo
        if [[ -n "$session_path" ]] && git -C "$session_path" rev-parse --git-dir &>/dev/null; then
            session_mode="W"  # Workspace
            local branch
            branch=$(git -C "$session_path" branch --show-current 2>/dev/null || echo "")
            local stats
            stats=$(git -C "$session_path" diff --numstat 2>/dev/null | awk '{add+=$1; del+=$2} END {if(add>0||del>0) printf "+%d,-%d", add, del}')
            git_info="${ICON_GIT} ${branch}"
            [[ -n "$stats" ]] && diff_info="$stats"
        else
            session_mode="S"  # Simple
            git_info="(no git)"
        fi

        # Session line
        local active_mark=""
        [[ "$session" == "$current_session" ]] && active_mark="${C_ACTIVE}${ICON_ACTIVE}${C_RESET} "

        printf "session:%s:%s %s[%s] %b%s%b  %b%s%b %b%s%b\n" \
            "$session" \
            "$ICON_SESSION" \
            "$active_mark" \
            "$session_mode" \
            "$C_SESSION" "$session" "$C_RESET" \
            "$C_GIT" "$git_info" "$C_RESET" \
            "$C_DIFF_ADD" "$diff_info" "$C_RESET"

        # Get windows for this session
        tmux list-windows -t "$session" -F '#{window_index}:#{window_name}:#{window_active}' 2>/dev/null | while read -r window_info; do
            local win_idx win_name win_active
            IFS=':' read -r win_idx win_name win_active <<< "$window_info"

            local win_mark=""
            [[ "$session" == "$current_session" && "$win_idx" == "$current_window" ]] && win_mark="${C_ACTIVE}${ICON_ACTIVE}${C_RESET}"

            printf "window:%s:%s:  ├─ %s %b%s: %s%b %s\n" \
                "$session" \
                "$win_idx" \
                "$ICON_WINDOW" \
                "$C_WINDOW" "$win_idx" "$win_name" "$C_RESET" \
                "$win_mark"

            # Get panes for this window
            tmux list-panes -t "${session}:${win_idx}" -F '#{pane_index}:#{pane_current_command}:#{pane_active}' 2>/dev/null | while read -r pane_info; do
                local pane_idx pane_cmd pane_active
                IFS=':' read -r pane_idx pane_cmd pane_active <<< "$pane_info"

                local pane_mark=""
                [[ "$session" == "$current_session" && "$win_idx" == "$current_window" && "$pane_idx" == "$current_pane" ]] && pane_mark="${C_ACTIVE}${ICON_ACTIVE}${C_RESET}"

                printf "pane:%s:%s:%s:  │  └─ %s %b%s: %s%b %s\n" \
                    "$session" \
                    "$win_idx" \
                    "$pane_idx" \
                    "$ICON_PANE" \
                    "$C_PANE" "$pane_idx" "$pane_cmd" "$C_RESET" \
                    "$pane_mark"
            done
        done
    done
}

# Parse selection and switch
handle_selection() {
    local selection="$1"
    local type target_session target_window target_pane

    IFS=':' read -r type target_session target_window target_pane _ <<< "$selection"

    case "$type" in
        session)
            tmux switch-client -t "$target_session" || handle_error "Failed to switch to session"
            ;;
        window)
            tmux switch-client -t "${target_session}:${target_window}" || handle_error "Failed to switch to window"
            ;;
        pane)
            tmux switch-client -t "${target_session}:${target_window}.${target_pane}" || handle_error "Failed to switch to pane"
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
        --bind="n:execute($SCRIPT_DIR/new-session.sh)+reload($SCRIPT_DIR/pilot.sh --list)" \
        --bind="r:execute($SCRIPT_DIR/rename.sh {})+reload($SCRIPT_DIR/pilot.sh --list)" \
        --bind="x:execute($SCRIPT_DIR/kill.sh {})+reload($SCRIPT_DIR/pilot.sh --list)" \
        --bind="D:preview($SCRIPT_DIR/diff.sh {})" \
        --bind="?:preview($SCRIPT_DIR/help.sh)" \
        --delimiter=':' \
    ) || exit 0

    [[ -n "$selection" ]] && handle_selection "$selection"
}

# If called with --list, just output the tree (for reload)
if [[ "$1" == "--list" ]]; then
    build_tree
else
    main
fi
