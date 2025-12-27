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

# Colors for navigator
readonly NAV_C_HEADER="\033[1;36m"
readonly NAV_C_SELECTED="\033[7m"  # Reverse video
readonly NAV_C_NORMAL="\033[0m"
readonly NAV_C_DIM="\033[2m"
readonly NAV_C_RUNNING="\033[32m"
readonly NAV_C_IDLE="\033[33m"
readonly NAV_C_EXITED="\033[31m"
readonly NAV_C_DORMANT="\033[90m"

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
    done < <(tmux list-sessions -F '#{session_name}	#{pane_current_command}' 2>/dev/null || true)

    # Add dormant sessions (metadata exists but no tmux session)
    for meta_file in "${TOWER_METADATA_DIR}"/*.meta; do
        [[ -f "$meta_file" ]] || continue

        local session_id
        session_id=$(basename "$meta_file" .meta)

        # Skip if already in list
        local found=0
        for id in "${SESSION_IDS[@]:-}"; do
            [[ "$id" == "$session_id" ]] && { found=1; break; }
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
    local max_lines=$((term_height - 8))  # Reserve space for header/footer

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
            local line
            line=$(printf '%s' "$display" | sed 's/\x1b\[[0-9;]*m//g' | cut -c1-22)
            local colored_line="$display"

            if [[ $i -eq $selected_index ]]; then
                # Highlight selected row
                printf "│${NAV_C_SELECTED}%-23s${NAV_C_NORMAL}│\n" " ${line}"
            else
                printf "│ %-22s │\n" "$line"
            fi
            ((i++)) || true
        done
    fi

    # Footer with keybindings
    echo -e "${NAV_C_HEADER}├─────────────────────────┤${NAV_C_NORMAL}"
    echo -e "│ ${NAV_C_DIM}j/k${NAV_C_NORMAL}:nav ${NAV_C_DIM}Enter${NAV_C_NORMAL}:attach   │"
    echo -e "│ ${NAV_C_DIM}i${NAV_C_NORMAL}:input ${NAV_C_DIM}n${NAV_C_NORMAL}:new ${NAV_C_DIM}d${NAV_C_NORMAL}:del   │"
    echo -e "│ ${NAV_C_DIM}R${NAV_C_NORMAL}:restart ${NAV_C_DIM}?${NAV_C_NORMAL}:help ${NAV_C_DIM}q${NAV_C_NORMAL}:quit│"
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
    echo "    i          Input mode (focus preview)"
    echo "    n          Create new session"
    echo "    d          Delete selected session"
    echo "    R          Restart Claude in session"
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

# Signal right pane to update preview
signal_preview_update() {
    # Send Escape to right pane to trigger detach/reattach
    nav_tmux send-keys -t "$TOWER_NAV_SESSION:0.1" Escape 2>/dev/null || true
}

# Move selection and update preview
move_selection() {
    local direction="$1"  # "up" or "down"
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
        signal_preview_update
    fi

    echo "$new_index"
}

# Go to first session
go_first() {
    if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
        set_nav_selected "${SESSION_IDS[0]}"
        signal_preview_update
    fi
    echo 0
}

# Go to last session
go_last() {
    if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
        local last_index=$((${#SESSION_IDS[@]} - 1))
        set_nav_selected "${SESSION_IDS[$last_index]}"
        signal_preview_update
        echo "$last_index"
    else
        echo 0
    fi
}

# Focus on input (right pane)
focus_input() {
    set_nav_focus "preview"
    nav_tmux select-pane -t "$TOWER_NAV_SESSION:0.1"
}

# Create new session
create_new_session() {
    # Use display-popup for session creation
    nav_tmux display-popup -E -w 60% -h 40% "$SCRIPT_DIR/session-new.sh" 2>/dev/null || {
        # Fallback: just run in current pane
        "$SCRIPT_DIR/session-new.sh"
    }
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
    read -rsn1 confirm

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

    # Send Ctrl-C and restart
    tmux send-keys -t "$selected" C-c 2>/dev/null || true
    sleep 0.2
    tmux send-keys -t "$selected" "${TOWER_PROGRAM:-claude}" Enter 2>/dev/null || true
    echo -e "\n${C_GREEN}Restarted Claude${C_RESET}"
    sleep 0.5
}

# Full attach to selected session
full_attach() {
    local selected
    selected=$(get_nav_selected)

    if [[ -z "$selected" ]]; then
        return
    fi

    # Check if dormant and restore
    local state
    state=$(get_session_state "$selected")

    if [[ "$state" == "$STATE_DORMANT" ]]; then
        echo "Restoring session..."
        "$SCRIPT_DIR/session-restore.sh" "$selected" 2>/dev/null || true
        sleep 0.5
    fi

    # Call navigator.sh to handle full attach
    exec "$SCRIPT_DIR/navigator.sh" --attach "$selected"
}

# Quit Navigator
quit_navigator() {
    exec "$SCRIPT_DIR/navigator.sh" --close
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
        signal_preview_update
    fi

    while true; do
        # Clear and render
        clear
        render_list "$selected_index"

        # Wait for input with timeout
        local key=""
        if read -rsn1 -t "$REFRESH_INTERVAL" key; then
            case "$key" in
                j|$'\x1b')
                    # Handle arrow keys
                    if [[ "$key" == $'\x1b' ]]; then
                        read -rsn2 -t 0.1 arrow || true
                        case "$arrow" in
                            '[B') key="j" ;;  # Down
                            '[A') key="k" ;;  # Up
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
                '')  # Enter key
                    full_attach
                    ;;
                i)
                    focus_input
                    ;;
                n)
                    create_new_session
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
                '?')
                    show_help
                    ;;
                q|Q)
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
