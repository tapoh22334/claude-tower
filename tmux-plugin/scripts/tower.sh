#!/usr/bin/env bash
# tower.sh - Main entry point for claude-tower
# A parallel Claude Code orchestrator
#
# Usage: tower.sh [command] [args...]
#
# Commands:
#   (none)      Launch Navigator UI
#   list        List all sessions
#   new         Create new session
#   delete      Delete session
#   restore     Restore dormant session(s)
#   tile        Launch Tile mode
#   help        Show help
#
# Environment:
#   CLAUDE_TOWER_PROGRAM      Program to run (default: claude)
#   CLAUDE_TOWER_WORKTREE_DIR Worktree directory
#   CLAUDE_TOWER_METADATA_DIR Metadata directory
#   CLAUDE_TOWER_DEBUG        Enable debug logging (1)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="tower.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

# Show help
show_help() {
    cat <<'EOF'
claude-tower - Parallel Claude Code Orchestrator

Usage: tower.sh [command] [args...]

Commands:
  (default)     Launch Navigator UI
  list          List all sessions
  add           Add directory as session
    PATH          Directory path
    -n NAME       Custom session name (default: dir basename)
  rm            Remove session
    SESSION_ID    Session to delete
    -f, --force   Skip confirmation
  restore       Restore dormant sessions
    SESSION_ID    Specific session to restore
    --all         Restore all dormant sessions
  tile          Launch Tile mode
  help          Show this help

Session States:
  ▶ Active      Session is running
  ○ Dormant     Session needs restoration

Key Bindings (in Navigator):
  j/k           Navigate sessions
  Enter         Attach to session
  i             Input mode (send command)
  t             Tile mode (view all)
  r             Restart Claude
  ?             Help
  Esc/q         Exit

Examples:
  tower.sh                           # Launch Navigator
  tower.sh add ~/projects/myapp      # Add directory as session
  tower.sh add . -n custom-name      # Add current dir with custom name
  tower.sh list                      # List all sessions
  tower.sh restore --all             # Restore dormant sessions
  tower.sh rm feat-login             # Delete session

EOF
}

# Main command handler
main() {
    local cmd="${1:-}"

    case "$cmd" in
        "" | navigator)
            # Default: Launch Navigator
            "$SCRIPT_DIR/navigator.sh"
            ;;
        list)
            shift
            "$SCRIPT_DIR/session-list.sh" "${1:-pretty}"
            ;;
        add)
            shift
            "$SCRIPT_DIR/session-add.sh" "$@"
            ;;
        rm)
            shift
            "$SCRIPT_DIR/session-delete.sh" "$@"
            ;;
        restore)
            shift
            "$SCRIPT_DIR/session-restore.sh" "$@"
            ;;
        tile)
            "$SCRIPT_DIR/tile.sh"
            ;;
        help | --help | -h)
            show_help
            ;;
        *)
            handle_error "Unknown command: $cmd"
            echo "Run 'tower.sh help' for usage"
            exit 1
            ;;
    esac
}

# Auto-restore dormant sessions on startup (if enabled)
if [[ "${CLAUDE_TOWER_AUTO_RESTORE:-0}" == "1" ]]; then
    restore_all_dormant
fi

main "$@"
