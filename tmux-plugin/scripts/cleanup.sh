#!/usr/bin/env bash
# cleanup.sh - Cleanup dormant sessions
# v2: Removes only metadata. Directories are never touched.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Show usage
show_usage() {
    cat <<EOF
Usage: cleanup.sh [OPTIONS]

Cleanup dormant session metadata.

Note: This only removes metadata files. Directories are never deleted.
      Use 'tower rm <name>' to remove individual sessions.

Options:
    -l, --list      List dormant sessions without removing
    -f, --force     Remove without confirmation
    -h, --help      Show this help message

Examples:
    cleanup.sh --list     # Show dormant sessions
    cleanup.sh            # Interactive cleanup with confirmation
    cleanup.sh --force    # Remove all dormant session metadata immediately
EOF
}

# Find dormant sessions (metadata exists but no tmux session)
find_dormant_sessions() {
    for meta_file in "${TOWER_METADATA_DIR}"/*.meta; do
        [[ -f "$meta_file" ]] || continue

        local session_id
        session_id=$(basename "$meta_file" .meta)

        # Check if tmux session exists
        if ! session_tmux has-session -t "$session_id" 2>/dev/null; then
            echo "$session_id"
        fi
    done
}

# List dormant sessions
list_dormant_sessions() {
    printf "%b━━━ Dormant Sessions ━━━%b\n" "$C_HEADER" "$C_RESET"
    echo ""

    local dormant_sessions
    dormant_sessions=$(find_dormant_sessions)

    if [[ -z "$dormant_sessions" ]]; then
        printf "%bNo dormant sessions found.%b\n" "$C_GREEN" "$C_RESET"
        return 0
    fi

    local count=0
    while read -r session_id; do
        [[ -z "$session_id" ]] && continue

        count=$((count + 1))

        if load_metadata "$session_id"; then
            printf "%b[%d]%b %s\n" "$C_YELLOW" "$count" "$C_RESET" "${session_id#tower_}"
            printf "    Path: %s\n" "$META_DIRECTORY_PATH"
            if [[ -n "$META_CREATED_AT" ]]; then
                printf "    Created: %s\n" "$META_CREATED_AT"
            fi
            echo ""
        fi
    done <<<"$dormant_sessions"

    printf "Total: %d dormant session(s)\n" "$count"
    return 0
}

# Cleanup dormant sessions interactively
cleanup_interactive() {
    local dormant_sessions
    dormant_sessions=$(find_dormant_sessions)

    if [[ -z "$dormant_sessions" ]]; then
        printf "%bNo dormant sessions found.%b\n" "$C_GREEN" "$C_RESET"
        return 0
    fi

    list_dormant_sessions
    echo ""

    if confirm "Remove all dormant session metadata?"; then
        remove_all_dormant_sessions "$dormant_sessions"
    else
        printf "Cleanup cancelled.\n"
    fi
}

# Remove all dormant sessions
remove_all_dormant_sessions() {
    local dormant_sessions="$1"

    local removed=0
    local failed=0

    while read -r session_id; do
        [[ -z "$session_id" ]] && continue

        printf "Removing: %s... " "${session_id#tower_}"

        if delete_metadata "$session_id"; then
            printf "%bOK%b\n" "$C_GREEN" "$C_RESET"
            removed=$((removed + 1))
        else
            printf "%bFailed%b\n" "$C_RED" "$C_RESET"
            failed=$((failed + 1))
        fi
    done <<<"$dormant_sessions"

    echo ""
    printf "Cleanup complete. Removed: %d, Failed: %d\n" "$removed" "$failed"
}

# Cleanup with force (no confirmation)
cleanup_force() {
    local dormant_sessions
    dormant_sessions=$(find_dormant_sessions)

    if [[ -z "$dormant_sessions" ]]; then
        printf "%bNo dormant sessions found.%b\n" "$C_GREEN" "$C_RESET"
        return 0
    fi

    remove_all_dormant_sessions "$dormant_sessions"
}

# Main
main() {
    case "${1:-}" in
        -l | --list)
            list_dormant_sessions
            ;;
        -f | --force)
            cleanup_force
            ;;
        -h | --help)
            show_usage
            ;;
        "")
            cleanup_interactive
            ;;
        *)
            printf "Unknown option: %s\n" "$1"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
