#!/usr/bin/env bash
# session-add.sh - Add a directory as a Tower session
# Usage: session-add.sh <path> [-n name]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="session-add.sh"

# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

show_help() {
    cat <<'EOF'
Add a directory as a Tower session

Usage: session-add.sh <path> [-n name]

Arguments:
  <path>              Directory path to add as session

Options:
  -n, --name NAME     Custom session name (default: directory basename)
  -h, --help          Show this help

Examples:
  session-add.sh ~/projects/myapp
  session-add.sh ~/projects/myapp -n custom-name
  session-add.sh .

EOF
}

# Parse arguments
directory_path=""
custom_name=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n | --name)
            custom_name="$2"
            shift 2
            ;;
        -h | --help)
            show_help
            exit 0
            ;;
        -*)
            handle_error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [[ -z "$directory_path" ]]; then
                directory_path="$1"
                shift
            else
                handle_error "Multiple paths specified. Only one path is allowed."
                exit 1
            fi
            ;;
    esac
done

# Validate path argument
if [[ -z "$directory_path" ]]; then
    handle_error "Directory path is required"
    show_help
    exit 1
fi

# Resolve to absolute path
if [[ "$directory_path" != /* ]]; then
    # Relative path - resolve from current directory
    current_dir=$(pwd)
    directory_path="${current_dir}/${directory_path}"
fi

# Normalize path (remove trailing slashes, resolve ..)
directory_path=$(cd "$directory_path" 2>/dev/null && pwd) || {
    handle_error "Directory does not exist: $directory_path"
    exit 1
}

# Validate directory exists
if [[ ! -d "$directory_path" ]]; then
    handle_error "Directory does not exist: $directory_path"
    exit 1
fi

# Determine session name
if [[ -n "$custom_name" ]]; then
    session_name="$custom_name"
else
    # Use directory basename
    session_name=$(basename "$directory_path")
fi

# Sanitize session name
sanitized_name=$(sanitize_name "$session_name")
if [[ -z "$sanitized_name" ]]; then
    handle_error "Invalid session name: $session_name"
    exit 1
fi

# Create session_id
session_id=$(normalize_session_name "$sanitized_name")

# Check for duplicate session
if session_exists "$session_id"; then
    handle_error "Session already exists: $sanitized_name"
    exit 1
fi

# Check if metadata already exists
if has_metadata "$session_id"; then
    handle_error "Session metadata already exists: $sanitized_name"
    exit 1
fi

debug_log "Creating session: name=$sanitized_name, path=$directory_path"

# Create session using common.sh function
# This will save metadata and start Claude
create_session "$sanitized_name" "simple" "$directory_path"
