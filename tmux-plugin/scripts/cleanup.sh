#!/usr/bin/env bash
# Cleanup orphaned worktrees and metadata
# Run this script to remove worktrees from sessions that no longer exist

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Show usage
show_usage() {
    cat << EOF
Usage: cleanup.sh [OPTIONS]

Cleanup orphaned worktrees and metadata from terminated sessions.

Options:
    -l, --list      List orphaned worktrees without removing
    -f, --force     Remove without confirmation
    -h, --help      Show this help message

Examples:
    cleanup.sh --list     # Show orphaned worktrees
    cleanup.sh            # Interactive cleanup with confirmation
    cleanup.sh --force    # Remove all orphaned worktrees immediately
EOF
}

# List orphaned worktrees
list_orphans() {
    printf "%b━━━ Orphaned Worktrees ━━━%b\n" "$C_HEADER" "$C_RESET"
    echo ""

    local orphans
    orphans=$(find_orphaned_worktrees)

    if [[ -z "$orphans" ]]; then
        printf "%bNo orphaned worktrees found.%b\n" "$C_GREEN" "$C_RESET"
        return 0
    fi

    local count=0
    while read -r session_name; do
        if [[ -z "$session_name" ]]; then
            continue
        fi

        count=$((count + 1))

        if load_metadata "$session_name"; then
            printf "%b[%d]%b %s\n" "$C_YELLOW" "$count" "$C_RESET" "$session_name"
            printf "    Mode: %s\n" "$META_MODE"
            if [[ -n "$META_WORKTREE_PATH" ]]; then
                printf "    Worktree: %s\n" "$META_WORKTREE_PATH"
                if [[ -d "$META_WORKTREE_PATH" ]]; then
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
    done <<< "$orphans"

    printf "Total: %d orphaned worktree(s)\n" "$count"
    return "$count"
}

# Cleanup orphans interactively
cleanup_interactive() {
    local orphans
    orphans=$(find_orphaned_worktrees)

    if [[ -z "$orphans" ]]; then
        printf "%bNo orphaned worktrees found.%b\n" "$C_GREEN" "$C_RESET"
        return 0
    fi

    list_orphans
    echo ""

    if confirm "Remove all orphaned worktrees?"; then
        cleanup_all "$orphans"
    else
        printf "Cleanup cancelled.\n"
    fi
}

# Cleanup all orphans
cleanup_all() {
    local orphans="$1"

    local removed=0
    local failed=0

    while read -r session_name; do
        if [[ -z "$session_name" ]]; then
            continue
        fi

        printf "Cleaning up: %s... " "$session_name"

        if cleanup_orphaned_worktree "$session_name"; then
            printf "%bOK%b\n" "$C_GREEN" "$C_RESET"
            removed=$((removed + 1))
        else
            printf "%bFailed%b\n" "$C_RED" "$C_RESET"
            failed=$((failed + 1))
        fi
    done <<< "$orphans"

    echo ""
    printf "Cleanup complete. Removed: %d, Failed: %d\n" "$removed" "$failed"
}

# Cleanup with force (no confirmation)
cleanup_force() {
    local orphans
    orphans=$(find_orphaned_worktrees)

    if [[ -z "$orphans" ]]; then
        printf "%bNo orphaned worktrees found.%b\n" "$C_GREEN" "$C_RESET"
        return 0
    fi

    cleanup_all "$orphans"
}

# Main
main() {
    case "${1:-}" in
        -l|--list)
            list_orphans
            ;;
        -f|--force)
            cleanup_force
            ;;
        -h|--help)
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
