#!/usr/bin/env bash
# tower.sh - Main entry point for claude-tower
# A parallel Claude Code orchestrator
#
# Usage: tower.sh [command] [args...]
#
# Commands:
#   (none)      Launch Navigator UI
#   list        List all sessions
#   add         Add or create a session
#   delete      Delete session
#   restore     Restore dormant session(s)
#   tile        Launch Tile mode
#   help        Show help
#
# Environment:
#   CLAUDE_TOWER_PROGRAM      Program to run (default: claude)
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

Usage: tower.sh list|add|delete|restore|tile|help

Commands:
  (default)     Launch Navigator UI
  list          List all sessions
  add           Add an existing session or start a new one
  delete        Delete session
    SESSION_ID    Session to delete
    --force       Skip confirmation
  restore       Restore a dormant session
    SESSION_ID    Specific session to restore
  tile          Launch Tile mode
  help          Show this help

Session States:
  ◉ Running     Claude is actively working
  ▶ Idle        Claude is waiting for input
  ! Exited      Claude process has exited
  ○ Dormant     Session needs restoration

Key Bindings (in Navigator):
  j/k           Navigate sessions
  Enter         Attach to session
  i             Input mode (send command)
  t             Tile mode (view all)
  n             New session
  d             Delete session
  r             Restart Claude
  ?             Help
  Esc/q         Exit

Examples:
  tower.sh                           # Launch Navigator
  tower.sh list                      # List all sessions
  tower.sh restore feat-login        # Restore a dormant session
  tower.sh delete feat-login         # Delete session

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
            exec "$SCRIPT_DIR/session-add.sh" "$@"
            ;;
        delete)
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

main "$@"
