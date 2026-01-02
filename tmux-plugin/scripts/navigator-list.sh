#!/usr/bin/env bash
# navigator-list.sh - Left pane: Session list with vim-style navigation
#
# This script runs in the left pane of Navigator.
# It displays the session list and handles navigation keys.
# When switching sessions, it updates the state file and signals the right pane.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# ============================================================================
# Configuration
# ============================================================================

readonly REFRESH_INTERVAL=2

# Colors for navigator (using $'...' syntax for actual escape sequences)
readonly NAV_C_HEADER=$'\033[1;36m'
readonly NAV_C_SELECTED=$'\033[7m' # Reverse video
readonly NAV_C_NORMAL=$'\033[0m'
readonly NAV_C_DIM=$'\033[2m'
# Colors (NAV_C_RUNNING used in future state detection)
# shellcheck disable=SC2034
readonly NAV_C_RUNNING=$'\033[32m'
readonly NAV_C_IDLE=$'\033[33m'
readonly NAV_C_EXITED=$'\033[31m'
readonly NAV_C_DORMANT=$'\033[90m'

# ============================================================================
# Session List Management
# ============================================================================

# Session arrays
declare -a SESSION_IDS=()
declare -a SESSION_DISPLAYS=()

# Build session list from default tmux server
build_session_list() {
    SESSION_IDS=()
    SESSION_DISPLAYS=()

    local program_name
    program_name=$(basename "$TOWER_PROGRAM")

    # Get active tower sessions from DEFAULT tmux server (not Navigator server)
    while IFS=$'\t' read -r session_id pane_cmd; do
        [[ -z "$session_id" ]] && continue
        [[ "$session_id" != tower_* ]] && continue

        local state_color state_icon type_icon name

        # Determine state based on pane command
        if [[ "$pane_cmd" == "$program_name" || "$pane_cmd" == "claude" ]]; then
            state_color="$NAV_C_IDLE"
            state_icon="▶"
        else
            state_color="$NAV_C_EXITED"
            state_icon="!"
        fi

        # Determine type (worktree vs simple)
        if has_metadata "$session_id"; then
            type_icon="[W]"
        else
            type_icon="[S]"
        fi

        name="${session_id#tower_}"

        SESSION_IDS+=("$session_id")
        SESSION_DISPLAYS+=("${state_color}${state_icon}${NAV_C_NORMAL} ${type_icon} ${name}")
    done < <(TMUX= tmux list-sessions -F '#{session_name}	#{pane_current_command}' 2>/dev/null || true)

    # Add dormant sessions (metadata exists but no tmux session)
    for meta_file in "${TOWER_METADATA_DIR}"/*.meta; do
        [[ -f "$meta_file" ]] || continue

        local session_id
        session_id=$(basename "$meta_file" .meta)

        # Skip if already in list
        local found=0
        for id in "${SESSION_IDS[@]:-}"; do
            [[ "$id" == "$session_id" ]] && {
                found=1
                break
            }
        done
        [[ $found -eq 1 ]] && continue

        local name="${session_id#tower_}"
        SESSION_IDS+=("$session_id")
        SESSION_DISPLAYS+=("${NAV_C_DORMANT}○${NAV_C_NORMAL} [W] ${name}")
    done
}

# Get current selection index from state
get_selection_index() {
    local selected
    selected=$(get_nav_selected)

    if [[ -z "$selected" ]]; then
        echo 0
        return
    fi

    local i=0
    for id in "${SESSION_IDS[@]:-}"; do
        if [[ "$id" == "$selected" ]]; then
            echo "$i"
            return
        fi
        ((i++)) || true
    done

    # Not found, return 0
    echo 0
}

# ============================================================================
# Rendering
# ============================================================================

# Render session list
render_list() {
    local selected_index="$1"
    local term_height
    term_height=$(tput lines 2>/dev/null || echo 24)
    local max_lines=$((term_height - 8)) # Reserve space for header/footer

    # Header
    echo -e "${NAV_C_HEADER}┌─ Sessions ─────────────┐${NAV_C_NORMAL}"

    if [[ ${#SESSION_IDS[@]} -eq 0 ]]; then
        echo -e "│ ${NAV_C_DIM}(no sessions)${NAV_C_NORMAL}           │"
    else
        local i=0
        for display in "${SESSION_DISPLAYS[@]}"; do
            if [[ $i -ge $max_lines ]]; then
                local remaining=$((${#SESSION_IDS[@]} - max_lines))
                echo -e "│ ${NAV_C_DIM}... +${remaining} more${NAV_C_NORMAL}"
                break
            fi

            # Truncate display to fit
            # Strip ANSI codes and truncate for display
            local plain_text
            plain_text=$(printf '%s' "$display" | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-22)

            if [[ $i -eq $selected_index ]]; then
                # Highlight selected row
                printf "│${NAV_C_SELECTED}%-23s${NAV_C_NORMAL}│\n" " ${plain_text}"
            else
                printf "│ %-22s │\n" "$plain_text"
            fi
            ((i++)) || true
        done
    fi

    # Footer with keybindings
    echo -e "${NAV_C_HEADER}├─────────────────────────┤${NAV_C_NORMAL}"
    echo -e "│ ${NAV_C_DIM}j/k${NAV_C_NORMAL}:nav ${NAV_C_DIM}Enter${NAV_C_NORMAL}:attach   │"
    echo -e "│ ${NAV_C_DIM}i${NAV_C_NORMAL}:input ${NAV_C_DIM}n${NAV_C_NORMAL}:new ${NAV_C_DIM}d${NAV_C_NORMAL}:del   │"
    echo -e "│ ${NAV_C_DIM}R${NAV_C_NORMAL}:restart ${NAV_C_DIM}Tab${NAV_C_NORMAL}:tile    │"
    echo -e "│ ${NAV_C_DIM}?${NAV_C_NORMAL}:help ${NAV_C_DIM}q${NAV_C_NORMAL}:quit          │"
    echo -e "${NAV_C_HEADER}└─────────────────────────┘${NAV_C_NORMAL}"
}

# Show help screen
show_help() {
    clear
    echo -e "${NAV_C_HEADER}Navigator Help${NAV_C_NORMAL}"
    echo ""
    echo "  Navigation:"
    echo "    j / ↓      Move down"
    echo "    k / ↑      Move up"
    echo "    g          Go to first session"
    echo "    G          Go to last session"
    echo ""
    echo "  Actions:"
    echo "    Enter      Full attach to session"
    echo "    i          Focus view pane (input mode)"
    echo "    n          Create new session"
    echo "    d          Delete selected session"
    echo "    R          Restart Claude in session"
    echo "    Tab        Switch to Tile view"
    echo ""
    echo "  Other:"
    echo "    ?          Show this help"
    echo "    q          Quit Navigator"
    echo ""
    echo -e "${NAV_C_DIM}Press any key to continue...${NAV_C_NORMAL}"
    read -rsn1
}

# ============================================================================
# Actions
# ============================================================================

# Signal view pane to update
signal_view_update() {
    # Send Escape to right pane to trigger detach/reattach
    nav_tmux send-keys -t "$TOWER_NAV_SESSION:0.1" Escape 2>/dev/null || true
}

# Move selection and update view
move_selection() {
    local direction="$1" # "up" or "down"
    local current_index="$2"
    local new_index

    if [[ "$direction" == "down" ]]; then
        new_index=$((current_index + 1))
        [[ $new_index -ge ${#SESSION_IDS[@]} ]] && new_index=0
    else
        new_index=$((current_index - 1))
        [[ $new_index -lt 0 ]] && new_index=$((${#SESSION_IDS[@]} - 1))
        [[ $new_index -lt 0 ]] && new_index=0
    fi

    if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
        local new_session="${SESSION_IDS[$new_index]}"
        set_nav_selected "$new_session"
        signal_view_update
    fi

    echo "$new_index"
}

# Go to first session
go_first() {
    if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
        set_nav_selected "${SESSION_IDS[0]}"
        signal_view_update
    fi
    echo 0
}

# Go to last session
go_last() {
    if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
        local last_index=$((${#SESSION_IDS[@]} - 1))
        set_nav_selected "${SESSION_IDS[$last_index]}"
        signal_view_update
        echo "$last_index"
    else
        echo 0
    fi
}

# Focus on view pane (enables input to selected session)
focus_view() {
    set_nav_focus "view"
    nav_tmux select-pane -t "$TOWER_NAV_SESSION:0.1"
}

# Create new session (inline input in list pane)
create_session_inline() {
    # Clear prompt area
    local term_height
    term_height=$(tput lines 2>/dev/null || echo 24)

    # Move cursor to bottom of list area
    tput cup "$((term_height - 4))" 0 2>/dev/null || true
    echo -e "${NAV_C_HEADER}┌─ New Session ───────────┐${NAV_C_NORMAL}"

    # Get session name
    printf "│ Name: "
    local name=""
    read -r name

    if [[ -z "$name" ]]; then
        echo -e "│ ${NAV_C_DIM}Cancelled${NAV_C_NORMAL}"
        sleep 0.5
        return
    fi

    # Ask about worktree
    printf "│ Worktree? [y/N]: "
    local worktree_choice=""
    read -rsn1 worktree_choice
    echo ""

    local use_worktree=0
    if [[ "$worktree_choice" == "y" || "$worktree_choice" == "Y" ]]; then
        use_worktree=1
    fi

    echo -e "${NAV_C_HEADER}└─────────────────────────┘${NAV_C_NORMAL}"

    # Create session
    local result
    if [[ $use_worktree -eq 1 ]]; then
        # Get current working directory from caller session or use pwd
        local working_dir
        working_dir=$(pwd)
        if result=$("$SCRIPT_DIR/session-new.sh" "$name" --worktree --dir "$working_dir" 2>&1); then
            echo -e "${C_GREEN}Created: $name${C_RESET}"
        else
            echo -e "${C_RED}Error: ${result}${C_RESET}"
        fi
    else
        if result=$("$SCRIPT_DIR/session-new.sh" "$name" 2>&1); then
            echo -e "${C_GREEN}Created: $name${C_RESET}"
        else
            echo -e "${C_RED}Error: ${result}${C_RESET}"
        fi
    fi
    sleep 0.5
}

# Delete selected session
delete_selected() {
    local selected
    selected=$(get_nav_selected)

    if [[ -z "$selected" ]]; then
        return
    fi

    local name="${selected#tower_}"

    echo -e "\n${C_YELLOW}Delete '${name}'? (y/N)${C_RESET}"
    if ! read -rsn1 -t 10 confirm; then
        echo -e "\n${NAV_C_DIM}Cancelled (timeout)${NAV_C_NORMAL}"
        return
    fi

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        "$SCRIPT_DIR/session-delete.sh" "$selected" --force 2>/dev/null || true
        echo -e "${C_GREEN}Deleted${C_RESET}"
        sleep 0.5
    fi
}

# Restart Claude in selected session
restart_selected() {
    local selected
    selected=$(get_nav_selected)

    if [[ -z "$selected" ]]; then
        return
    fi

    # Send Ctrl-C and restart on DEFAULT server
    TMUX= tmux send-keys -t "$selected" C-c 2>/dev/null || true
    sleep 0.2
    TMUX= tmux send-keys -t "$selected" "${TOWER_PROGRAM:-claude}" Enter 2>/dev/null || true
    echo -e "\n${C_GREEN}Restarted Claude${C_RESET}"
    sleep 0.5
}

# Switch to Tile mode
switch_to_tile() {
    info_log "Switching to Tile mode"

    # Create tile window on default server first
    TMUX= tmux new-window -n "tower-tile" "$SCRIPT_DIR/tile.sh" 2>/dev/null || true

    # Get the current session to return to (should have the new tile window)
    local target_session
    target_session=$(TMUX= tmux display-message -p '#S' 2>/dev/null || echo "")

    if [[ -z "$target_session" ]]; then
        target_session=$(TMUX= tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")
    fi

    if [[ -n "$target_session" ]]; then
        nav_tmux detach-client -E "TMUX= tmux attach-session -t '$target_session'"
    fi
}

# Full attach to selected session
# Uses detach-client -E to seamlessly switch from Navigator to the target session
full_attach() {
    local selected
    selected=$(get_nav_selected)

    if [[ -z "$selected" ]]; then
        return
    fi

    # Check if dormant and restore first
    local state
    state=$(get_session_state "$selected")

    if [[ "$state" == "$STATE_DORMANT" ]]; then
        echo "Restoring session..."
        "$SCRIPT_DIR/session-restore.sh" "$selected" 2>/dev/null || true
        sleep 0.5
        # Re-check state after restore
        state=$(get_session_state "$selected")
    fi

    # Verify session exists on default server
    if ! TMUX= tmux has-session -t "$selected" 2>/dev/null; then
        handle_error "Session not found: ${selected#tower_}"
        return 1
    fi

    info_log "Full attach to session: $selected"

    # Use detach-client -E to seamlessly switch from Navigator server to default server
    # This detaches the client from Navigator and immediately attaches to the target session
    # The Navigator session remains alive in the background for fast re-entry
    nav_tmux detach-client -E "TMUX= tmux attach-session -t '$selected'"
}

# Quit Navigator
# Returns to the caller session or any available session on default server
quit_navigator() {
    local caller
    caller=$(get_nav_caller)

    info_log "Quitting Navigator, returning to caller: ${caller:-<none>}"

    # Determine target session on default server
    local target_session=""
    if [[ -n "$caller" ]] && TMUX= tmux has-session -t "$caller" 2>/dev/null; then
        target_session="$caller"
    else
        # Fallback: find any session on default server
        target_session=$(TMUX= tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")
    fi

    if [[ -n "$target_session" ]]; then
        # Use detach-client -E to seamlessly return to default server
        nav_tmux detach-client -E "TMUX= tmux attach-session -t '$target_session'"
    else
        # No sessions available, just exit
        nav_tmux detach-client
    fi
}

# ============================================================================
# Main Loop
# ============================================================================

main_loop() {
    # Initial build
    build_session_list

    # Get initial selection
    local selected_index
    selected_index=$(get_selection_index)

    # Set initial selection if not set
    if [[ ${#SESSION_IDS[@]} -gt 0 && -z "$(get_nav_selected)" ]]; then
        set_nav_selected "${SESSION_IDS[0]}"
        signal_view_update
    fi

    while true; do
        # Clear and render
        clear
        render_list "$selected_index"

        # Wait for input with timeout
        local key=""
        if read -rsn1 -t "$REFRESH_INTERVAL" key; then
            case "$key" in
                j | $'\x1b')
                    # Handle arrow keys
                    if [[ "$key" == $'\x1b' ]]; then
                        read -rsn2 -t 0.1 arrow || true
                        case "$arrow" in
                            '[B') key="j" ;; # Down
                            '[A') key="k" ;; # Up
                            *) continue ;;
                        esac
                    fi
                    if [[ "$key" == "j" ]]; then
                        selected_index=$(move_selection "down" "$selected_index")
                    fi
                    ;;
                k)
                    selected_index=$(move_selection "up" "$selected_index")
                    ;;
                g)
                    selected_index=$(go_first)
                    ;;
                G)
                    selected_index=$(go_last)
                    ;;
                '') # Enter key
                    full_attach
                    ;;
                i)
                    focus_view
                    ;;
                n)
                    create_session_inline
                    build_session_list
                    ;;
                d)
                    delete_selected
                    build_session_list
                    selected_index=$(get_selection_index)
                    ;;
                R)
                    restart_selected
                    ;;
                $'\t') # Tab key
                    switch_to_tile
                    ;;
                '?')
                    show_help
                    ;;
                q | Q)
                    quit_navigator
                    ;;
            esac
        else
            # Timeout - refresh session list
            build_session_list

            # Clamp selection
            if [[ $selected_index -ge ${#SESSION_IDS[@]} ]]; then
                selected_index=$((${#SESSION_IDS[@]} - 1))
                [[ $selected_index -lt 0 ]] && selected_index=0
                if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
                    set_nav_selected "${SESSION_IDS[$selected_index]}"
                fi
            fi
        fi
    done
}

# ============================================================================
# Main
# ============================================================================

main_loop
