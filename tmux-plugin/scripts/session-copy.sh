#!/usr/bin/env bash
# session-copy.sh - Copy a session: a new Tower session that continues the
# source's conversation under a new id, in the same directory.
# Usage: session-copy.sh <session_id> [--print-id]
# --print-id: print the new tower_<uuid> id on stdout (for Navigator).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="session-copy.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

PRINT_ID=0
arg=""
for a in "$@"; do
    case "$a" in
        --print-id) PRINT_ID=1 ;;
        -*)
            handle_error "Unknown option: $a"
            exit 1
            ;;
        *) arg="$a" ;;
    esac
done

if [[ -z "$arg" ]]; then
    handle_error "Usage: session-copy.sh <session_id> [--print-id]"
    exit 1
fi

# Validate and ensure the tower_ prefix (security: prevent injection)
session_id=$(ensure_tower_prefix "$arg") || {
    handle_error "Invalid session ID format"
    exit 1
}

new_id=$(copy_session "$session_id") || exit 1
if [[ "$PRINT_ID" -eq 1 ]]; then
    echo "$new_id"
else
    handle_success "Copied to ${new_id#tower_}" >&2
fi
