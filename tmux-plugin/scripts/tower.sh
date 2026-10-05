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
#   rename      Set or clear a session's Navigator display name
#   open        Start a new session in a directory (optional initial prompt)
#   project new Create a project directory, git init, start its first session
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

Usage: tower.sh list|add|rename|open|project new|delete|restore|tile|help

Commands:
  (default)     Launch Navigator UI
  list          List all sessions
  add           Add an existing session or start a new one
  rename        Set the Navigator display name of a session
    NAME          New name (omit the session inside a Tower pane)
    --session ID  Target session (required outside a Tower pane)
    --clear       Remove the name, back to the first-prompt title
  open          Start a new session in a directory and show it in Navigator
    DIR           Project directory
    --prompt TEXT        First prompt for the new session
    --prompt-file PATH   First prompt from a file (- = stdin)
  project new   Create DIR under ~/working, git init, start its first session
    NAME          Project name (one path component)
    --in PARENT   Parent directory instead of ~/working
    --prompt / --prompt-file  as for open
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
  tower.sh rename "payments 移行"     # Rename the session you are in
  tower.sh open ~/working/foo --prompt-file -   # New session there, prompt from stdin
  tower.sh project new bar           # ~/working/bar + git init + first session

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
        rename)
            shift
            exec "$SCRIPT_DIR/session-rename.sh" "$@"
            ;;
        open)
            shift
            exec "$SCRIPT_DIR/session-open.sh" "$@"
            ;;
        project)
            shift
            case "${1:-}" in
                new)
                    shift
                    exec "$SCRIPT_DIR/project-new.sh" "$@"
                    ;;
                *)
                    handle_error "Unknown project subcommand: ${1:-<none>} (expected: new)"
                    echo "Run 'tower.sh help' for usage"
                    exit 2
                    ;;
            esac
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
