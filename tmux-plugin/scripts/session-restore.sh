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
    # Validate and ensure session_id has tower_ prefix (security: prevent injection)
    session_id=$(ensure_tower_prefix "$arg") || {
        handle_error "Invalid session ID format"
        exit 1
    }
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

    # Build tmux display-menu dynamically
    menu_items=()
    idx=1
    for sid in "${dormant_sessions[@]}"; do
        # Menu format: "label" "key" "command"
        menu_items+=("$sid" "$idx" "run-shell '$SCRIPT_DIR/session-restore.sh tower_$sid'")
        ((idx++))
    done

    # Show menu
    if [[ ${#menu_items[@]} -gt 0 ]]; then
        tmux display-menu -T "Restore Dormant Session" "${menu_items[@]}" 2>/dev/null
    else
        echo "Dormant sessions:"
        printf '%s\n' "${dormant_sessions[@]}"
    fi
fi
