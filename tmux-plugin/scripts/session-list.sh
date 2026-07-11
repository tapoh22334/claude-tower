#!/usr/bin/env bash
# session-list.sh - List all claude-tower sessions
# Usage: session-list.sh [--format FORMAT]
#   FORMAT: raw (default), pretty, json

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="session-list.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

format="${1:-raw}"

case "$format" in
    raw | --raw)
        list_all_sessions
        ;;
    pretty | --pretty)
        while IFS=':' read -r session_id state; do
            [[ -z "$session_id" ]] && continue

            state_icon=$(get_state_icon "$state")
            display_name="${session_id#tower_}"

            printf "%s %-25s\n" "$state_icon" "$display_name"
        done < <(list_all_sessions)
        ;;
    json | --json)
        echo "["
        first=true
        while IFS=':' read -r session_id state; do
            [[ -z "$session_id" ]] && continue
            [[ "$first" == "true" ]] && first=false || echo ","
            cat <<EOF
  {
    "session_id": "$session_id",
    "state": "$state"
  }
EOF
        done < <(list_all_sessions)
        echo "]"
        ;;
    *)
        handle_error "Unknown format: $format"
        exit 1
        ;;
esac
