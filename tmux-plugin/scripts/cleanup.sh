#!/usr/bin/env bash
# Cleanup orphaned worktrees and metadata
# Run this script to remove worktrees from sessions that no longer exist

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Show usage
show_usage() {
    cat <<EOF
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
list_orphaned_worktrees() {
    printf "%b━━━ Orphaned Worktrees ━━━%b\n" "$C_HEADER" "$C_RESET"
    echo ""

    local orphaned_worktrees
    orphaned_worktrees=$(find_orphaned_worktrees)

    if [[ -z "$orphaned_worktrees" ]]; then
        printf "%bNo orphaned worktrees found.%b\n" "$C_GREEN" "$C_RESET"
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
            printf "    Session Type: %s\n" "$META_SESSION_TYPE"
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
    done <<<"$orphaned_worktrees"

    printf "Total: %d orphaned worktree(s)\n" "$count"
    return "$count"
}

# Cleanup orphaned worktrees interactively
cleanup_interactive() {
    local orphaned_worktrees
    orphaned_worktrees=$(find_orphaned_worktrees)

    if [[ -z "$orphaned_worktrees" ]]; then
        printf "%bNo orphaned worktrees found.%b\n" "$C_GREEN" "$C_RESET"
        return 0
    fi

    list_orphaned_worktrees
    echo ""

    if confirm "Remove all orphaned worktrees?"; then
        remove_all_orphaned_worktrees "$orphaned_worktrees"
    else
        printf "Cleanup cancelled.\n"
    fi
}

# Remove all orphaned worktrees
remove_all_orphaned_worktrees() {
    local orphaned_worktrees="$1"

    local removed=0
    local failed=0

    while read -r session_id; do
        if [[ -z "$session_id" ]]; then
            continue
        fi

        printf "Removing: %s... " "$session_id"

        if remove_orphaned_worktree "$session_id"; then
            printf "%bOK%b\n" "$C_GREEN" "$C_RESET"
            removed=$((removed + 1))
        else
            printf "%bFailed%b\n" "$C_RED" "$C_RESET"
            failed=$((failed + 1))
        fi
    done <<<"$orphaned_worktrees"

    echo ""
    printf "Cleanup complete. Removed: %d, Failed: %d\n" "$removed" "$failed"
}

# Cleanup with force (no confirmation)
cleanup_force() {
    local orphaned_worktrees
    orphaned_worktrees=$(find_orphaned_worktrees)

    if [[ -z "$orphaned_worktrees" ]]; then
        printf "%bNo orphaned worktrees found.%b\n" "$C_GREEN" "$C_RESET"
        return 0
    fi

    remove_all_orphaned_worktrees "$orphaned_worktrees"
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
