#!/usr/bin/env bash
# cleanup.sh - Cleanup orphaned session metadata
# Removes metadata for sessions that no longer have active tmux sessions.
# Directories are never touched.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Show usage
show_usage() {
    cat <<EOF
Usage: cleanup.sh [OPTIONS]

Cleanup orphaned metadata from terminated sessions.

Note: This only removes metadata files. Directories are never deleted.
      Use 'tower rm <name>' to remove individual sessions.

Options:
    -l, --list      List orphaned metadata without removing
    -f, --force     Remove without confirmation
    -h, --help      Show this help message

Examples:
    cleanup.sh --list     # Show orphaned metadata
    cleanup.sh            # Interactive cleanup with confirmation
    cleanup.sh --force    # Remove all orphaned metadata immediately
EOF
}

# List orphaned metadata
list_orphaned() {
    printf "%b━━━ Orphaned Metadata ━━━%b\n" "$C_HEADER" "$C_RESET"
    echo ""

    local orphaned
    orphaned=$(find_orphaned_metadata)

    if [[ -z "$orphaned" ]]; then
        printf "%bNo orphaned metadata found.%b\n" "$C_GREEN" "$C_RESET"
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
    done <<<"$orphaned"

    printf "Total: %d orphaned metadata file(s)\n" "$count"
    return 0
}

# Cleanup orphaned metadata interactively
cleanup_interactive() {
    local orphaned
    orphaned=$(find_orphaned_metadata)

    if [[ -z "$orphaned" ]]; then
        printf "%bNo orphaned metadata found.%b\n" "$C_GREEN" "$C_RESET"
        return 0
    fi

    list_orphaned
    echo ""

    if confirm "Remove all orphaned metadata?"; then
        remove_all_orphaned "$orphaned"
    else
        printf "Cleanup cancelled.\n"
    fi
}

# Remove all orphaned metadata
remove_all_orphaned() {
    local orphaned="$1"

    local removed=0
    local failed=0

    while read -r session_id; do
        [[ -z "$session_id" ]] && continue

        printf "Removing: %s... " "${session_id#tower_}"

        if remove_orphaned_metadata "$session_id"; then
            printf "%bOK%b\n" "$C_GREEN" "$C_RESET"
            removed=$((removed + 1))
        else
            printf "%bFailed%b\n" "$C_RED" "$C_RESET"
            failed=$((failed + 1))
        fi
    done <<<"$orphaned"

    echo ""
    printf "Cleanup complete. Removed: %d, Failed: %d\n" "$removed" "$failed"
}

# Cleanup with force (no confirmation)
cleanup_force() {
    local orphaned
    orphaned=$(find_orphaned_metadata)

    if [[ -z "$orphaned" ]]; then
        printf "%bNo orphaned metadata found.%b\n" "$C_GREEN" "$C_RESET"
        return 0
    fi

    remove_all_orphaned "$orphaned"
}

# Main
main() {
    case "${1:-}" in
        -l | --list)
            list_orphaned
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
