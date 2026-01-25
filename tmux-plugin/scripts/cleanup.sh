#!/usr/bin/env bash
# Cleanup orphaned metadata
# Run this script to remove metadata from sessions that no longer exist

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Show usage
show_usage() {
    cat <<EOF
Usage: cleanup.sh [OPTIONS]

Cleanup orphaned metadata from terminated sessions.

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
list_orphaned_metadata() {
    printf "%b━━━ Orphaned Metadata ━━━%b\n" "$C_HEADER" "$C_RESET"
    echo ""

    local orphaned_metadata
    orphaned_metadata=$(find_orphaned_metadata)

    if [[ -z "$orphaned_metadata" ]]; then
        printf "%bNo orphaned metadata found.%b\n" "$C_GREEN" "$C_RESET"
        return 0
    fi

    local count=0
    while read -r session_id; do
        if [[ -z "$session_id" ]]; then
            continue
        fi

        count=$((count + 1))

        if load_metadata "$session_id"; then
            printf "%b[%d]%b %s\n" "$C_YELLOW" "$count" "$C_RESET" "$session_id"
            printf "    Session Name: %s\n" "$META_SESSION_NAME"
            if [[ -n "$META_DIRECTORY_PATH" ]]; then
                printf "    Directory: %s\n" "$META_DIRECTORY_PATH"
                if [[ -d "$META_DIRECTORY_PATH" ]]; then
                    printf "    Status: %bExists%b\n" "$C_GREEN" "$C_RESET"
                else
                    printf "    Status: %bNot found%b\n" "$C_RED" "$C_RESET"
                fi
            fi
            if [[ -n "$META_CREATED_AT" ]]; then
                printf "    Created: %s\n" "$META_CREATED_AT"
            fi
            echo ""
        fi
    done <<<"$orphaned_metadata"

    printf "Total: %d orphaned metadata file(s)\n" "$count"
    return "$count"
}

# Cleanup orphaned metadata interactively
cleanup_interactive() {
    local orphaned_metadata
    orphaned_metadata=$(find_orphaned_metadata)

    if [[ -z "$orphaned_metadata" ]]; then
        printf "%bNo orphaned metadata found.%b\n" "$C_GREEN" "$C_RESET"
        return 0
    fi

    list_orphaned_metadata
    echo ""

    if confirm "Remove all orphaned metadata?"; then
        remove_all_orphaned_metadata "$orphaned_metadata"
    else
        printf "Cleanup cancelled.\n"
    fi
}

# Remove all orphaned metadata
remove_all_orphaned_metadata() {
    local orphaned_metadata="$1"

    local removed=0
    local failed=0

    while read -r session_id; do
        if [[ -z "$session_id" ]]; then
            continue
        fi

        printf "Removing: %s... " "$session_id"

        if remove_orphaned_metadata "$session_id"; then
            printf "%bOK%b\n" "$C_GREEN" "$C_RESET"
            removed=$((removed + 1))
        else
            printf "%bFailed%b\n" "$C_RED" "$C_RESET"
            failed=$((failed + 1))
        fi
    done <<<"$orphaned_metadata"

    echo ""
    printf "Cleanup complete. Removed: %d, Failed: %d\n" "$removed" "$failed"
}

# Cleanup with force (no confirmation)
cleanup_force() {
    local orphaned_metadata
    orphaned_metadata=$(find_orphaned_metadata)

    if [[ -z "$orphaned_metadata" ]]; then
        printf "%bNo orphaned metadata found.%b\n" "$C_GREEN" "$C_RESET"
        return 0
    fi

    remove_all_orphaned_metadata "$orphaned_metadata"
}

# Main
main() {
    case "${1:-}" in
        -l | --list)
            list_orphaned_worktrees
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
