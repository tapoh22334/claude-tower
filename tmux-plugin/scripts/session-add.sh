#!/usr/bin/env bash
# session-add.sh - Add a new claude-tower session (v2)
# Usage: session-add.sh <path> [-n|--name <name>]
#
# Creates a session for the specified directory and starts Claude Code.
# The directory is referenced, not managed - tower never creates or deletes directories.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="session-add.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

show_help() {
    cat <<'EOF'
Add a new claude-tower session

Usage: session-add.sh <path> [-n|--name <name>]

Arguments:
  path                  Working directory path (required)

Options:
  -n, --name <name>     Session name (default: directory name)
  --no-attach           Don't attach to new session after creation
  -h, --help            Show this help

Examples:
  session-add.sh .                        # Add session for current directory
  session-add.sh /path/to/project         # Add session for specified path
  session-add.sh . -n my-project          # Add with custom session name

EOF
}

# Parse arguments
path=""
name=""
no_attach=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n | --name)
            if [[ $# -lt 2 ]]; then
                echo "Error: --name requires a value" >&2
                exit 1
            fi
            name="$2"
            shift 2
            ;;
        --no-attach)
            no_attach=true
            shift
            ;;
        -h | --help)
            show_help
            exit 0
            ;;
        -*)
            echo "Error: Unknown option: $1" >&2
            echo "Run 'session-add.sh --help' for usage." >&2
            exit 1
            ;;
        *)
            if [[ -z "$path" ]]; then
                path="$1"
            else
                echo "Error: Unexpected argument: $1" >&2
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate path argument
if [[ -z "$path" ]]; then
    echo "Error: Path is required" >&2
    echo "Usage: session-add.sh <path> [-n|--name <name>]" >&2
    exit 1
fi

# Resolve to absolute path
if [[ "$path" == "." ]]; then
    path="$(pwd)"
elif [[ "$path" != /* ]]; then
    path="$(cd "$path" 2>/dev/null && pwd)" || {
        echo "Error: Directory does not exist: $path" >&2
        exit 1
    }
fi

# Validate path exists
if [[ ! -e "$path" ]]; then
    echo "Error: Directory does not exist: $path" >&2
    exit 1
fi

# Validate path is a directory
if [[ ! -d "$path" ]]; then
    echo "Error: Not a directory: $path" >&2
    exit 1
fi

# Derive session name from directory if not specified
if [[ -z "$name" ]]; then
    name="$(basename "$path")"
fi

# Sanitize and validate name
sanitized_name=$(sanitize_name "$name")
if [[ -z "$sanitized_name" ]]; then
    echo "Error: Invalid session name: $name" >&2
    exit 1
fi

# Check for existing session
session_id=$(normalize_session_name "$sanitized_name")
if session_exists "$session_id" || has_metadata "$session_id"; then
    echo "Error: Session already exists: $sanitized_name" >&2
    exit 1
fi

# Create session
debug_log "Creating session: name=$sanitized_name, path=$path"

if create_session "$sanitized_name" "$path"; then
    # Output success message per CLI contract
    echo "Session created: $sanitized_name"
    echo "  Path: $path"

    # Attach to new session (unless --no-attach)
    if [[ "$no_attach" != "true" ]]; then
        session_tmux switch-client -t "$session_id" 2>/dev/null ||
            session_tmux attach-session -t "$session_id" 2>/dev/null || true
    fi
else
    exit 1
fi
