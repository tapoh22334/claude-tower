#!/usr/bin/env bash
# navigator.sh - Main Navigator UI for claude-tower
# Provides session selection, preview, and operations using fzf
#
# Key bindings:
#   Enter     - Attach to selected session
#   i         - Input mode (send command to session)
#   t         - Switch to Tile mode
#   n         - Create new session
#   d         - Delete session
#   r         - Restart Claude in session
#   ?         - Show help
#   Esc/q     - Exit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="navigator.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Check dependencies
require_command fzf || exit 1

# Generate session list for fzf
# Format: "state_icon type_icon display_name [branch] [diff_stats]|session_id"
generate_session_list() {
    while IFS=':' read -r session_id state type display_name branch diff_stats; do
        [[ -z "$session_id" ]] && continue

        local state_icon type_icon branch_info diff_info line
        state_icon=$(get_state_icon "$state")
        type_icon=$(get_type_icon "$type")

        branch_info=""
        [[ -n "$branch" ]] && branch_info=" ${ICON_GIT} $branch"

        diff_info=""
        [[ -n "$diff_stats" ]] && diff_info=" $diff_stats"

        # Format: visible_part|session_id (session_id hidden by fzf delimiter)
        line=$(printf "%s %s %-25s%s%s" \
            "$state_icon" "$type_icon" "$display_name" "$branch_info" "$diff_info")

        echo "${line}|${session_id}"
    done < <(list_all_sessions)
}

# Preview script for selected session
generate_preview() {
    local session_id="$1"
    [[ -z "$session_id" ]] && return

    local state
    state=$(get_session_state "$session_id")

    # Header
    echo -e "${C_HEADER}━━━ Session: ${session_id#tower_} ━━━${C_RESET}"
    echo ""

    # Show session info
    local type working_dir
    type=$(get_session_type "$session_id")
    echo -e "${C_INFO}Type:${C_RESET} $(get_type_icon "$type") $type"
    echo -e "${C_INFO}State:${C_RESET} $(get_state_icon "$state") $state"

    if [[ "$state" != "$STATE_DORMANT" ]]; then
        working_dir=$(tmux display-message -t "$session_id" -p '#{pane_current_path}' 2>/dev/null || echo "")
        [[ -n "$working_dir" ]] && echo -e "${C_INFO}Dir:${C_RESET} $working_dir"
    elif load_metadata "$session_id" 2>/dev/null; then
        echo -e "${C_INFO}Dir:${C_RESET} $META_WORKTREE_PATH"
    fi

    echo ""
    echo -e "${C_HEADER}━━━ Output ━━━${C_RESET}"
    echo ""

    # Show pane content if active
    if [[ "$state" != "$STATE_DORMANT" ]]; then
        tmux capture-pane -t "$session_id" -p -S -30 2>/dev/null | tail -25 || echo "(no output)"
    else
        echo "(session is dormant - press Enter to restore)"
    fi
}

# Handle keyboard actions
handle_action() {
    local action="$1"
    local session_id="$2"

    case "$action" in
        enter|"")
            # Attach to session
            if [[ -n "$session_id" ]]; then
                local state
                state=$(get_session_state "$session_id")

                if [[ "$state" == "$STATE_DORMANT" ]]; then
                    restore_session "$session_id"
                fi

                tmux switch-client -t "$session_id" 2>/dev/null || \
                tmux attach-session -t "$session_id" 2>/dev/null || true
            fi
            ;;
        input)
            # Switch to input mode
            if [[ -n "$session_id" ]]; then
                "$SCRIPT_DIR/input.sh" "$session_id"
            fi
            ;;
        tile)
            # Switch to tile mode
            "$SCRIPT_DIR/tile.sh"
            ;;
        new)
            # Create new session
            "$SCRIPT_DIR/session-new.sh"
            ;;
        delete)
            # Delete session
            if [[ -n "$session_id" ]]; then
                "$SCRIPT_DIR/session-delete.sh" "$session_id"
            fi
            ;;
        restart)
            # Restart session
            if [[ -n "$session_id" ]]; then
                restart_session "$session_id"
            fi
            ;;
        help)
            show_help
            ;;
    esac
}

# Show help in fzf
show_help() {
    cat << 'EOF' | fzf-tmux -p 60%,60% \
        --header="Claude Tower - Help" \
        --no-info \
        --prompt="" \
        --bind="enter:abort,esc:abort,q:abort"

 ╔══════════════════════════════════════════════════════╗
 ║               claude-tower Navigator                 ║
 ╠══════════════════════════════════════════════════════╣
 ║                                                      ║
 ║  Navigation:                                         ║
 ║    j / ↓      Move down                              ║
 ║    k / ↑      Move up                                ║
 ║    Enter      Attach to selected session             ║
 ║    Esc / q    Exit Navigator                         ║
 ║                                                      ║
 ║  Actions:                                            ║
 ║    i          Input mode (send command)              ║
 ║    t          Tile mode (view all sessions)          ║
 ║    n          New session                            ║
 ║    d          Delete session                         ║
 ║    r          Restart Claude                         ║
 ║    ?          Show this help                         ║
 ║                                                      ║
 ║  Session States:                                     ║
 ║    ◉ Running  Claude is actively working             ║
 ║    ▶ Idle     Claude is waiting for input            ║
 ║    ! Exited   Claude process has exited              ║
 ║    ○ Dormant  Session needs restoration              ║
 ║                                                      ║
 ║  Session Types:                                      ║
 ║    [W] Worktree  Persistent (auto-restores)          ║
 ║    [S] Simple    Volatile (lost on restart)          ║
 ║                                                      ║
 ║  Press any key to close                              ║
 ╚══════════════════════════════════════════════════════╝

EOF
}

# Main fzf interface
run_navigator() {
    local preview_cmd="$SCRIPT_DIR/navigator.sh --preview {2}"

    # Export preview function for subshell
    export -f generate_preview get_session_state get_session_type get_state_icon get_type_icon
    export -f load_metadata has_metadata
    export TOWER_METADATA_DIR TOWER_PROGRAM STATE_DORMANT STATE_RUNNING STATE_IDLE STATE_EXITED
    export TYPE_WORKTREE TYPE_SIMPLE
    export ICON_STATE_RUNNING ICON_STATE_IDLE ICON_STATE_EXITED ICON_STATE_DORMANT
    export ICON_TYPE_WORKTREE ICON_TYPE_SIMPLE ICON_GIT
    export C_HEADER C_INFO C_RESET

    local result
    result=$(generate_session_list | fzf-tmux -p 90%,80% \
        --ansi \
        --delimiter='|' \
        --with-nth=1 \
        --preview="$preview_cmd" \
        --preview-window='right:50%:wrap' \
        --header="$(printf '%b' "${C_HEADER}Claude Tower${C_RESET} │ i:input t:tile n:new d:delete r:restart ?:help")" \
        --prompt="Session: " \
        --pointer="▶" \
        --marker="●" \
        --bind='j:down,k:up' \
        --bind='ctrl-j:down,ctrl-k:up' \
        --bind='i:execute(echo input {2})+abort' \
        --bind='t:execute(echo tile)+abort' \
        --bind='n:execute(echo new)+abort' \
        --bind='d:execute(echo delete {2})+abort' \
        --bind='r:execute(echo restart {2})+abort' \
        --bind='?:execute(echo help)+abort' \
        --bind='enter:accept' \
        --bind='esc:abort,q:abort' \
        --expect='enter' \
        --no-info \
        2>/dev/null) || true

    # Parse result
    if [[ -n "$result" ]]; then
        local key selected_line action session_id
        key=$(echo "$result" | head -1)
        selected_line=$(echo "$result" | tail -1)

        # Check if result is an action command
        if [[ "$selected_line" =~ ^(input|tile|new|delete|restart|help) ]]; then
            action=$(echo "$selected_line" | awk '{print $1}')
            session_id=$(echo "$selected_line" | awk '{print $2}')
        else
            action="enter"
            session_id=$(echo "$selected_line" | awk -F'|' '{print $2}')
        fi

        handle_action "$action" "$session_id"

        # Reload navigator after actions (except enter and tile)
        case "$action" in
            new|delete|restart|help)
                run_navigator
                ;;
        esac
    fi
}

# Handle preview mode (called by fzf)
if [[ "${1:-}" == "--preview" ]]; then
    generate_preview "$2"
    exit 0
fi

# Main entry point
run_navigator
