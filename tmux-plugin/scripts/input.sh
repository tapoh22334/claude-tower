#!/usr/bin/env bash
# input.sh - Input mode for claude-tower
# Allows sending commands to a session without switching to it
#
# Usage: input.sh <session_id>
#
# Key bindings:
#   Enter      - Send input to session
#   Ctrl-[     - Return to Navigator (Vim style)
#   Esc        - Return to Navigator

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="input.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

session_id="${1:-}"

if [[ -z "$session_id" ]]; then
    handle_error "Session ID required"
    exit 1
fi

# Ensure session_id has tower_ prefix
[[ "$session_id" != tower_* ]] && session_id="tower_$session_id"

# Check session state
state=$(get_session_state "$session_id")

if [[ -z "$state" ]]; then
    handle_error "Session does not exist: ${session_id#tower_}"
    exit 1
fi

if [[ "$state" == "$STATE_DORMANT" ]]; then
    handle_error "Session is dormant. Restore it first."
    exit 1
fi

display_name="${session_id#tower_}"

# Function to capture current session output for preview
generate_session_preview() {
    echo -e "${C_HEADER}━━━ $display_name ━━━${C_RESET}"
    echo ""
    tmux capture-pane -t "$session_id" -p -S -20 2>/dev/null | tail -15 || echo "(no output)"
}

# Input loop using fzf
run_input_mode() {
    while true; do
        # Generate current preview
        local preview
        preview=$(generate_session_preview)

        # Get input from user
        local input
        input=$(echo "" | fzf-tmux -p 80%,70% \
            --ansi \
            --print-query \
            --header="$(printf '%b' "${C_HEADER}Input Mode${C_RESET} → $display_name │ Enter:send Ctrl-[:exit")" \
            --prompt=">>> " \
            --preview="echo '$preview'" \
            --preview-window='up:60%:wrap' \
            --no-info \
            --bind='ctrl-[:abort' \
            --bind='esc:abort' \
            2>/dev/null | head -1) || break

        # If input is empty, user pressed Esc or Ctrl-[
        if [[ -z "$input" ]]; then
            break
        fi

        # Send input to session
        send_to_session "$session_id" "$input"

        # Brief pause to let Claude process
        sleep 0.3
    done

    # Return to Navigator
    "$SCRIPT_DIR/navigator.sh"
}

# Alternative: Direct tmux read-line approach
run_input_mode_simple() {
    local input=""

    while true; do
        # Show current output
        clear
        echo -e "${C_HEADER}━━━ Input Mode: $display_name ━━━${C_RESET}"
        echo -e "${C_INFO}Enter command (Ctrl-C to exit):${C_RESET}"
        echo ""

        # Show session preview
        tmux capture-pane -t "$session_id" -p -S -15 2>/dev/null | tail -10 || echo "(no output)"

        echo ""
        echo -e "${C_HEADER}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"

        # Read input
        read -r -p ">>> " input || break

        if [[ -n "$input" ]]; then
            send_to_session "$session_id" "$input"
            sleep 0.5
        fi
    done
}

# Use fzf-based input mode
run_input_mode
