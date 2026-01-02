#!/usr/bin/env bash
# Tree View - Enhanced tree display with prefix-w style layout
# Core rendering logic shared between overlay and sidebar

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="tree-view.sh"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Tree drawing characters
readonly TREE_BRANCH="├─"
readonly TREE_LAST="└─"
readonly TREE_PIPE="│ "
readonly TREE_SPACE="  "

# Build enhanced tree structure with more details
build_enhanced_tree() {
    local active_session active_window active_pane
    local show_panes="${1:-true}"
    local compact="${2:-false}"

    active_session=$(tmux display-message -p '#S')
    active_window=$(tmux display-message -p '#I')
    active_pane=$(tmux display-message -p '#P')

    # Get all sessions
    local sessions
    sessions=$(tmux list-sessions -F '#{session_name}:#{session_attached}:#{session_windows}' 2>/dev/null)
    local session_count
    session_count=$(echo "$sessions" | wc -l)
    local current_session_idx=0

    while IFS=':' read -r session attached win_count; do
        ((current_session_idx++)) || true
        local is_last_session="false"
        [[ $current_session_idx -eq $session_count ]] && is_last_session="true"

        local session_path session_type git_info diff_stats=""
        local display_name="${session#tower_}"

        # Get session's current path
        session_path=$(tmux display-message -t "$session" -p '#{pane_current_path}' 2>/dev/null || echo "")

        # Determine session type and git info
        if [[ "$session" == tower_* ]] && load_metadata "$session" 2>/dev/null; then
            session_type="$META_SESSION_TYPE"
            if [[ "$session_type" == "workspace" && -n "$META_WORKTREE_PATH" ]]; then
                session_path="$META_WORKTREE_PATH"
            fi
        else
            if [[ -n "$session_path" ]] && git -C "$session_path" rev-parse --git-dir &>/dev/null; then
                session_type="workspace"
            else
                session_type="simple"
            fi
        fi

        # Git information
        if [[ "$session_type" == "workspace" && -n "$session_path" ]]; then
            local branch
            branch=$(git -C "$session_path" branch --show-current 2>/dev/null || echo "detached")

            # Diff stats
            local stats
            stats=$(git -C "$session_path" diff --numstat 2>/dev/null |
                awk '{add+=$1; del+=$2} END {if(add>0||del>0) printf "+%d,-%d", add, del}')

            git_info="${ICON_GIT} ${branch}"
            [[ -n "$stats" ]] && diff_stats="$stats"
        else
            git_info="(no git)"
        fi

        # Session line formatting
        local type_indicator="S"
        [[ "$session_type" == "workspace" ]] && type_indicator="W"
        local active_marker=""
        [[ "$session" == "$active_session" ]] && active_marker="${C_ACTIVE}${ICON_ACTIVE}${C_RESET} "
        local attached_marker=""
        [[ "$attached" -gt 0 ]] && attached_marker="(attached)"

        # Output session line with selection prefix
        printf "session:%s:%s %s[%s] %b%-20s%b %b%-15s%b %b%s%b %s\n" \
            "$session" \
            "$ICON_SESSION" \
            "$active_marker" \
            "$type_indicator" \
            "$C_SESSION" "$display_name" "$C_RESET" \
            "$C_GIT" "$git_info" "$C_RESET" \
            "$C_DIFF_ADD" "${diff_stats:-}" "$C_RESET" \
            "$attached_marker"

        # Skip windows/panes in compact mode
        [[ "$compact" == "true" ]] && continue

        # Get windows for this session
        local windows window_total current_window_idx=0
        windows=$(tmux list-windows -t "$session" -F '#{window_index}:#{window_name}:#{window_active}:#{window_panes}' 2>/dev/null) || continue
        window_total=$(echo "$windows" | wc -l | tr -d ' ')

        while IFS=':' read -r win_idx win_name win_active pane_count; do
            ((current_window_idx++)) || true
            local is_last_window="false"
            [[ $current_window_idx -eq $window_total ]] && is_last_window="true"

            local window_prefix
            if [[ "$is_last_window" == "true" ]]; then
                window_prefix="  ${TREE_LAST}"
            else
                window_prefix="  ${TREE_BRANCH}"
            fi

            local window_active_marker=""
            [[ "$session" == "$active_session" && "$win_idx" == "$active_window" ]] &&
                window_active_marker=" ${C_ACTIVE}${ICON_ACTIVE}${C_RESET}"

            printf "window:%s:%s:%s %s %b%s: %s%b%s\n" \
                "$session" \
                "$win_idx" \
                "$window_prefix" \
                "$ICON_WINDOW" \
                "$C_WINDOW" "$win_idx" "$win_name" "$C_RESET" \
                "$window_active_marker"

            # Skip panes if not requested
            [[ "$show_panes" != "true" ]] && continue

            # Get panes for this window
            local panes pane_total current_pane_idx=0
            panes=$(tmux list-panes -t "${session}:${win_idx}" -F '#{pane_index}:#{pane_current_command}:#{pane_active}:#{pane_pid}' 2>/dev/null) || continue
            pane_total=$(echo "$panes" | wc -l | tr -d ' ')

            while IFS=':' read -r pane_idx pane_cmd pane_is_active pane_pid; do
                ((current_pane_idx++)) || true
                local is_last_pane="false"
                [[ $current_pane_idx -eq $pane_total ]] && is_last_pane="true"

                local pane_prefix_parent
                if [[ "$is_last_window" == "true" ]]; then
                    pane_prefix_parent="  ${TREE_SPACE}"
                else
                    pane_prefix_parent="  ${TREE_PIPE}"
                fi

                local pane_prefix_self
                if [[ "$is_last_pane" == "true" ]]; then
                    pane_prefix_self="${TREE_LAST}"
                else
                    pane_prefix_self="${TREE_BRANCH}"
                fi

                local pane_active_marker=""
                [[ "$session" == "$active_session" && "$win_idx" == "$active_window" && "$pane_idx" == "$active_pane" ]] &&
                    pane_active_marker=" ${C_ACTIVE}${ICON_ACTIVE}${C_RESET}"

                printf "pane:%s:%s:%s:%s%s %s %b%s: %s%b (pid:%s)%s\n" \
                    "$session" \
                    "$win_idx" \
                    "$pane_idx" \
                    "$pane_prefix_parent" \
                    "$pane_prefix_self" \
                    "$ICON_PANE" \
                    "$C_PANE" "$pane_idx" "$pane_cmd" "$C_RESET" \
                    "$pane_pid" \
                    "$pane_active_marker"
            done <<<"$panes"
        done <<<"$windows"
    done <<<"$sessions"
}

# Build compact session-only list
build_session_list() {
    build_enhanced_tree false true
}

# Build full tree with all details
build_full_tree() {
    build_enhanced_tree true false
}

# Main
case "${1:-full}" in
    compact | sessions)
        build_session_list
        ;;
    windows)
        build_enhanced_tree false false
        ;;
    full | *)
        build_full_tree
        ;;
esac
