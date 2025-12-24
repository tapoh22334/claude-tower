#!/usr/bin/env bash
# session-restore.sh - Restore a dormant session or all dormant sessions
# Usage: session-restore.sh [session_id | --all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="session-restore.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

arg="${1:-}"

if [[ "$arg" == "--all" || "$arg" == "-a" ]]; then
    restore_all_dormant
elif [[ -n "$arg" ]]; then
    session_id="$arg"
    # Ensure session_id has tower_ prefix
    [[ "$session_id" != tower_* ]] && session_id="tower_$session_id"
    restore_session "$session_id"
else
    # Interactive: select from dormant sessions
    dormant_sessions=()

    for meta_file in "${TOWER_METADATA_DIR}"/*.meta; do
        [[ -f "$meta_file" ]] || continue
        sid=$(basename "$meta_file" .meta)
        state=$(get_session_state "$sid")
        if [[ "$state" == "$STATE_DORMANT" ]]; then
            dormant_sessions+=("${sid#tower_}")
        fi
    done

    if [[ ${#dormant_sessions[@]} -eq 0 ]]; then
        handle_info "No dormant sessions to restore"
        exit 0
    fi

    # Use fzf to select
    if command -v fzf &>/dev/null; then
        selected=$(printf '%s\n' "${dormant_sessions[@]}" | fzf-tmux -p 60%,40% \
            --header="Select session to restore:" \
            --prompt="Session: " \
            --no-info) || exit 0

        if [[ -n "$selected" ]]; then
            restore_session "tower_$selected"
        fi
    else
        echo "Dormant sessions:"
        printf '%s\n' "${dormant_sessions[@]}"
    fi
fi
