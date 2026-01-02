#!/usr/bin/env bash
# input.sh - Input mode for claude-tower
# Allows sending commands to a session without switching to it
#
# Usage: input.sh <session_id>
#
# Key bindings:
#   Enter      - Send input to session
#   Ctrl-C     - Exit input mode
#   Ctrl-D     - Exit input mode

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

# Colors
readonly NC=$'\033[0m'
readonly BOLD=$'\033[1m'
readonly DIM=$'\033[2m'
readonly CYAN=$'\033[36m'
readonly YELLOW=$'\033[33m'

# Draw header
draw_header() {
    clear
    echo -e "${BOLD}${CYAN}━━━ Input Mode: $display_name ━━━${NC}"
    echo -e "${DIM}Enter command and press Enter. Ctrl-C/Ctrl-D to exit.${NC}"
    echo ""
}

# Show session preview
show_preview() {
    echo -e "${DIM}─── Session Output ───${NC}"
    tmux capture-pane -t "$session_id" -p -S -15 2>/dev/null | tail -12 || echo "(no output)"
    echo -e "${DIM}──────────────────────${NC}"
    echo ""
}

# Main input loop
main() {
    trap 'echo ""; exit 0' INT TERM

    while true; do
        draw_header
        show_preview

        # Read input
        echo -ne "${YELLOW}>>> ${NC}"
        read -r input || break # Ctrl-D exits

        if [[ -n "$input" ]]; then
            send_to_session "$session_id" "$input"
            echo -e "${DIM}Sent. Waiting...${NC}"
            sleep 0.5
        fi
    done
}

main
