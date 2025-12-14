#!/usr/bin/env bash
# Common library for claude-tower
# This file should be sourced by other scripts

# Strict mode
set -euo pipefail

# ============================================================================
# Colors
# ============================================================================
readonly C_RESET="\033[0m"
readonly C_HEADER="\033[1;36m"    # Cyan bold
readonly C_SESSION="\033[1;34m"   # Blue bold
readonly C_WINDOW="\033[0;36m"    # Cyan
readonly C_PANE="\033[0;37m"      # Gray
readonly C_ACTIVE="\033[1;32m"    # Green bold
readonly C_GIT="\033[0;33m"       # Yellow
readonly C_GREEN="\033[0;32m"
readonly C_YELLOW="\033[0;33m"
readonly C_BLUE="\033[0;34m"
readonly C_RED="\033[0;31m"
readonly C_DIFF_ADD="\033[0;32m"  # Green
readonly C_DIFF_DEL="\033[0;31m"  # Red
readonly C_HUNK="\033[0;36m"      # Cyan
readonly C_INFO="\033[0;33m"      # Yellow

# ============================================================================
# Icons
# ============================================================================
readonly ICON_SESSION="📁"
readonly ICON_WINDOW="🪟"
readonly ICON_PANE="▫"
readonly ICON_ACTIVE="●"
readonly ICON_GIT="⎇"

# ============================================================================
# Configuration
# ============================================================================
readonly TOWER_WORKTREE_DIR="${CLAUDE_TOWER_WORKTREE_DIR:-$HOME/.claude-tower/worktrees}"
readonly TOWER_PROGRAM="${CLAUDE_TOWER_PROGRAM:-claude}"
readonly TOWER_METADATA_DIR="${CLAUDE_TOWER_METADATA_DIR:-$HOME/.claude-tower/metadata}"
readonly PREVIEW_LINES=30

# ============================================================================
# Input Sanitization
# ============================================================================
# These functions handle user input security:
# - sanitize_name: Removes dangerous characters (prevents command injection)
# - validate_path_within: Prevents path traversal attacks (e.g., ../../etc/passwd)
# - normalize_session_name: Converts user input to internal session_id format
#
# Processing flow: user_input → sanitize_name → normalize_session_name → session_id

# Sanitize session/branch name to prevent path traversal and command injection
# Security: Removes all characters except alphanumeric, hyphen, and underscore
#           to prevent shell injection and path traversal attacks
# Arguments:
#   $1 - Input string to sanitize (user_input)
# Returns:
#   Sanitized string (empty if input is entirely invalid)
sanitize_name() {
    local input="$1"
    # Remove any characters that aren't alphanumeric, hyphen, or underscore
    # Also collapse multiple underscores/hyphens and trim leading/trailing ones
    echo "$input" | tr -cd '[:alnum:]_-' | sed 's/^[-_]*//;s/[-_]*$//' | head -c 64
}

# Validate that a path is within the expected directory (prevent path traversal)
# Security: Prevents directory traversal attacks by ensuring resolved path
#           stays within the allowed base directory
# Arguments:
#   $1 - Path to validate
#   $2 - Expected base directory
# Returns:
#   0 if valid, 1 if invalid (path escapes base directory)
validate_path_within() {
    local path="$1"
    local base="$2"

    # Resolve to absolute paths
    local resolved_path resolved_base
    resolved_path=$(realpath -m "$path" 2>/dev/null) || return 1
    resolved_base=$(realpath -m "$base" 2>/dev/null) || return 1

    # Check if path starts with base
    [[ "$resolved_path" == "$resolved_base"* ]]
}

# Normalize session name to create session_id
# Converts sanitized user input to internal tmux session identifier format
# Arguments:
#   $1 - Sanitized session name
# Returns:
#   Session ID with tower_ prefix (e.g., "tower_my-project")
normalize_session_name() {
    local name="$1"
    echo "tower_${name}" | tr ' .' '_'
}

# ============================================================================
# Error Handling
# ============================================================================

# Display error message to user via tmux and stderr
# Arguments:
#   $1 - Error message
handle_error() {
    local msg="$1"
    echo "Error: $msg" >&2
    tmux display-message "Error: $msg" 2>/dev/null || true
}

# Display warning message to user via tmux
# Arguments:
#   $1 - Warning message
handle_warning() {
    local msg="$1"
    echo "Warning: $msg" >&2
    tmux display-message "Warning: $msg" 2>/dev/null || true
}

# Display info message to user via tmux
# Arguments:
#   $1 - Info message
handle_info() {
    local msg="$1"
    tmux display-message "$msg" 2>/dev/null || true
}

# ============================================================================
# Dependency Checks
# ============================================================================

# Check if required command is available
# Arguments:
#   $1 - Command name
# Returns:
#   0 if available, 1 if not
require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        handle_error "$cmd is required but not installed"
        return 1
    fi
    return 0
}

# ============================================================================
# Confirmation Dialog
# ============================================================================

# Show confirmation dialog using fzf
# Arguments:
#   $1 - Message to display
# Returns:
#   0 if confirmed (Yes), 1 if declined (No) or error
confirm() {
    local msg="$1"
    local result
    result=$(echo -e "Yes\nNo" | fzf-tmux -p 40%,20% \
        --header="$msg" \
        --no-info \
    ) || return 1
    [[ "$result" == "Yes" ]]
}

# ============================================================================
# Metadata Management
# ============================================================================
# Metadata is stored as simple key=value files for each session.
# This allows recovery of session info even if tmux session options are lost.

# Ensure metadata directory exists
ensure_metadata_dir() {
    mkdir -p "$TOWER_METADATA_DIR"
}

# Save session metadata to file
# Arguments:
#   $1 - Session ID (with tower_ prefix)
#   $2 - Session type (workspace|simple)
#   $3 - Repository path (optional, for workspace session type)
#   $4 - Source commit (optional, for workspace session type)
save_metadata() {
    local session_id="$1"
    local session_type="$2"
    local repository_path="${3:-}"
    local source_commit="${4:-}"

    ensure_metadata_dir

    local metadata_file="${TOWER_METADATA_DIR}/${session_id}.meta"

    {
        echo "session_id=${session_id}"
        echo "session_type=${session_type}"
        echo "created_at=$(date -Iseconds)"
        echo "repository_path=${repository_path}"
        echo "source_commit=${source_commit}"
        echo "worktree_path=${TOWER_WORKTREE_DIR}/${session_id#tower_}"
    } > "$metadata_file"
}

# Load session metadata from file
# Arguments:
#   $1 - Session ID
# Returns:
#   Exports variables: META_SESSION_TYPE, META_REPOSITORY_PATH, META_SOURCE_COMMIT, META_WORKTREE_PATH
load_metadata() {
    local session_id="$1"
    local metadata_file="${TOWER_METADATA_DIR}/${session_id}.meta"

    # Initialize with empty values
    META_SESSION_TYPE=""
    META_REPOSITORY_PATH=""
    META_SOURCE_COMMIT=""
    META_WORKTREE_PATH=""
    META_CREATED_AT=""

    if [[ -f "$metadata_file" ]]; then
        while IFS='=' read -r key value; do
            case "$key" in
                # Support both old and new key names for backwards compatibility
                mode|session_type) META_SESSION_TYPE="$value" ;;
                repo_path|repository_path) META_REPOSITORY_PATH="$value" ;;
                base_commit|source_commit) META_SOURCE_COMMIT="$value" ;;
                worktree_path) META_WORKTREE_PATH="$value" ;;
                created_at) META_CREATED_AT="$value" ;;
            esac
        done < "$metadata_file"
        return 0
    fi
    return 1
}

# Delete session metadata file
# Arguments:
#   $1 - Session ID
delete_metadata() {
    local session_id="$1"
    local metadata_file="${TOWER_METADATA_DIR}/${session_id}.meta"

    if [[ -f "$metadata_file" ]]; then
        rm -f "$metadata_file"
    fi
}

# List all metadata files
# Returns:
#   List of session IDs with metadata
list_metadata() {
    ensure_metadata_dir

    for meta_file in "${TOWER_METADATA_DIR}"/*.meta; do
        if [[ -f "$meta_file" ]]; then
            basename "$meta_file" .meta
        fi
    done
}

# Check if session has metadata
# Arguments:
#   $1 - Session ID
# Returns:
#   0 if exists, 1 if not
has_metadata() {
    local session_id="$1"
    [[ -f "${TOWER_METADATA_DIR}/${session_id}.meta" ]]
}

# ============================================================================
# Orphaned Worktree Detection and Cleanup
# ============================================================================
# Orphaned worktrees are worktrees that exist but have no corresponding
# active tmux session. These can occur when sessions are terminated
# unexpectedly or when cleanup fails.

# Get list of active tmux sessions
get_active_sessions() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null || true
}

# Find orphaned worktrees (worktrees without active sessions)
# Returns:
#   List of orphaned session IDs
find_orphaned_worktrees() {
    local active_sessions
    active_sessions=$(get_active_sessions)

    for meta_file in "${TOWER_METADATA_DIR}"/*.meta; do
        if [[ -f "$meta_file" ]]; then
            local session_id
            session_id=$(basename "$meta_file" .meta)

            # Check if session is active
            if ! echo "$active_sessions" | grep -q "^${session_id}$"; then
                echo "$session_id"
            fi
        fi
    done
}

# Remove orphaned worktree and its metadata
# Arguments:
#   $1 - Session ID
# Returns:
#   0 on success, 1 on failure
remove_orphaned_worktree() {
    local session_id="$1"

    if ! load_metadata "$session_id"; then
        return 1
    fi

    if [[ "$META_SESSION_TYPE" != "workspace" ]]; then
        # Simple session type - just delete metadata
        delete_metadata "$session_id"
        return 0
    fi

    local worktree_path="$META_WORKTREE_PATH"
    local repository_path="$META_REPOSITORY_PATH"

    if [[ -d "$worktree_path" ]]; then
        # Validate path before removal
        if validate_path_within "$worktree_path" "$TOWER_WORKTREE_DIR"; then
            if [[ -n "$repository_path" ]] && [[ -d "$repository_path" ]]; then
                git -C "$repository_path" worktree remove "$worktree_path" 2>/dev/null || \
                git -C "$repository_path" worktree remove --force "$worktree_path" 2>/dev/null || true
            else
                # Repository not found, remove directory manually
                rm -rf "$worktree_path"
            fi
        fi
    fi

    delete_metadata "$session_id"
    return 0
}

# Alias for backwards compatibility
cleanup_orphaned_worktree() {
    remove_orphaned_worktree "$@"
}
