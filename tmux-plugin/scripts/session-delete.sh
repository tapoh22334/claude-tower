#!/usr/bin/env bash
# session-delete.sh - Delete a claude-tower session
# Usage: session-delete.sh [session_id] [--force]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="session-delete.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

session_id="${1:-}"
force="${2:-}"

if [[ -z "$session_id" ]]; then
    handle_error "Session ID is required"
    exit 1
fi

# Validate and ensure session_id has tower_ prefix (security: prevent injection)
session_id=$(ensure_tower_prefix "$session_id") || {
    handle_error "Invalid session ID format"
    exit 1
}

delete_session "$session_id" "$force"
