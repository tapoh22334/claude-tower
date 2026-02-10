#!/usr/bin/env bash
# session-delete.sh - Delete a claude-tower session (v2)
# Usage: session-delete.sh <name> [-f|--force]
#
# Deletes the session (tmux session + metadata).
# v2: Directories are NEVER deleted - they are only referenced.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="session-delete.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

show_help() {
    cat <<'EOF'
Delete a claude-tower session

Usage: session-delete.sh <name> [-f|--force]

Arguments:
  name                  Session name to delete (required)

Options:
  -f, --force           Skip confirmation prompt
  -h, --help            Show this help

Note: This command only removes the session. The directory is NOT deleted.

Examples:
  session-delete.sh my-project          # Delete with confirmation
  session-delete.sh my-project -f       # Delete without confirmation

EOF
}

# Parse arguments
session_name=""
force=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f | --force)
            force="-f"
            shift
            ;;
        -h | --help)
            show_help
            exit 0
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            echo "Run 'session-delete.sh --help' for usage." >&2
            exit 1
            ;;
        *)
            if [[ -z "$session_name" ]]; then
                session_name="$1"
            else
                echo "Error: Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$session_name" ]]; then
    echo "Error: Session name is required" >&2
    echo "Usage: session-delete.sh <name> [-f|--force]" >&2
    exit 1
fi

# Validate and ensure session_id has tower_ prefix (security: prevent injection)
session_id=$(ensure_tower_prefix "$session_name") || {
    echo "Error: Invalid session name format" >&2
    exit 1
}

# Delete session (v2: never deletes directories)
if delete_session "$session_id" "$force"; then
    echo "Session deleted: ${session_id#tower_}"
else
    exit 1
fi
