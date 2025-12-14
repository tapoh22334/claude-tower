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

# Sanitize session/branch name to prevent path traversal and command injection
# Only allows alphanumeric characters, hyphens, and underscores
# Arguments:
#   $1 - Input string to sanitize
# Returns:
#   Sanitized string (empty if input is entirely invalid)
sanitize_name() {
    local input="$1"
    # Remove any characters that aren't alphanumeric, hyphen, or underscore
    # Also collapse multiple underscores/hyphens and trim leading/trailing ones
    echo "$input" | tr -cd '[:alnum:]_-' | sed 's/^[-_]*//;s/[-_]*$//' | head -c 64
}

# Validate that a path is within the expected directory (prevent path traversal)
# Arguments:
#   $1 - Path to validate
#   $2 - Expected base directory
# Returns:
#   0 if valid, 1 if invalid
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

# Normalize session name (replace spaces and dots with underscores)
# Arguments:
#   $1 - Session name
# Returns:
#   Normalized session name
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
#   $1 - Session name (sanitized)
#   $2 - Mode (workspace|simple)
#   $3 - Repository path (optional, for workspace mode)
#   $4 - Base commit (optional, for workspace mode)
save_metadata() {
    local session_name="$1"
    local mode="$2"
    local repo_path="${3:-}"
    local base_commit="${4:-}"

    ensure_metadata_dir

    local metadata_file="${TOWER_METADATA_DIR}/${session_name}.meta"

    {
        echo "session_name=${session_name}"
        echo "mode=${mode}"
        echo "created_at=$(date -Iseconds)"
        echo "repo_path=${repo_path}"
        echo "base_commit=${base_commit}"
        echo "worktree_path=${TOWER_WORKTREE_DIR}/${session_name#tower_}"
    } > "$metadata_file"
}

# Load session metadata from file
# Arguments:
#   $1 - Session name
# Returns:
#   Exports variables: META_MODE, META_REPO_PATH, META_BASE_COMMIT, META_WORKTREE_PATH
load_metadata() {
    local session_name="$1"
    local metadata_file="${TOWER_METADATA_DIR}/${session_name}.meta"

    # Initialize with empty values
    META_MODE=""
    META_REPO_PATH=""
    META_BASE_COMMIT=""
    META_WORKTREE_PATH=""
    META_CREATED_AT=""

    if [[ -f "$metadata_file" ]]; then
        while IFS='=' read -r key value; do
            case "$key" in
                mode) META_MODE="$value" ;;
                repo_path) META_REPO_PATH="$value" ;;
                base_commit) META_BASE_COMMIT="$value" ;;
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
#   $1 - Session name
delete_metadata() {
    local session_name="$1"
    local metadata_file="${TOWER_METADATA_DIR}/${session_name}.meta"

    if [[ -f "$metadata_file" ]]; then
        rm -f "$metadata_file"
    fi
}

# List all metadata files
# Returns:
#   List of session names with metadata
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
#   $1 - Session name
# Returns:
#   0 if exists, 1 if not
has_metadata() {
    local session_name="$1"
    [[ -f "${TOWER_METADATA_DIR}/${session_name}.meta" ]]
}

# ============================================================================
# Orphan Detection and Cleanup
# ============================================================================

# Get list of active tmux sessions
get_active_sessions() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null || true
}

# Find orphaned worktrees (worktrees without active sessions)
# Returns:
#   List of orphaned session names
find_orphaned_worktrees() {
    local active_sessions
    active_sessions=$(get_active_sessions)

    for meta_file in "${TOWER_METADATA_DIR}"/*.meta; do
        if [[ -f "$meta_file" ]]; then
            local session_name
            session_name=$(basename "$meta_file" .meta)

            # Check if session is active
            if ! echo "$active_sessions" | grep -q "^${session_name}$"; then
                echo "$session_name"
            fi
        fi
    done
}

# Cleanup orphaned worktree
# Arguments:
#   $1 - Session name
# Returns:
#   0 on success, 1 on failure
cleanup_orphaned_worktree() {
    local session_name="$1"

    if ! load_metadata "$session_name"; then
        return 1
    fi

    if [[ "$META_MODE" != "workspace" ]]; then
        # Simple mode - just delete metadata
        delete_metadata "$session_name"
        return 0
    fi

    local worktree_path="$META_WORKTREE_PATH"
    local repo_path="$META_REPO_PATH"

    if [[ -d "$worktree_path" ]]; then
        # Validate path before removal
        if validate_path_within "$worktree_path" "$TOWER_WORKTREE_DIR"; then
            if [[ -n "$repo_path" ]] && [[ -d "$repo_path" ]]; then
                git -C "$repo_path" worktree remove "$worktree_path" 2>/dev/null || \
                git -C "$repo_path" worktree remove --force "$worktree_path" 2>/dev/null || true
            else
                # Repo not found, remove directory manually
                rm -rf "$worktree_path"
            fi
        fi
    fi

    delete_metadata "$session_name"
    return 0
}
