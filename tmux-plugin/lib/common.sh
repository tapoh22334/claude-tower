#!/usr/bin/env bash
# Common library for claude-tower
# This file should be sourced by other scripts

# Strict mode
set -euo pipefail

# ============================================================================
# Error Trap and Debug Mode
# ============================================================================
# Enable debug mode with: export CLAUDE_TOWER_DEBUG=1
readonly TOWER_DEBUG="${CLAUDE_TOWER_DEBUG:-0}"

# Log file path (always available, not just in debug mode)
readonly TOWER_LOG_DIR="${CLAUDE_TOWER_METADATA_DIR:-$HOME/.claude-tower/metadata}"
readonly TOWER_LOG_FILE="${TOWER_LOG_DIR}/tower.log"

# Store the calling script name for error messages
TOWER_SCRIPT_NAME="${TOWER_SCRIPT_NAME:-${BASH_SOURCE[1]:-unknown}}"
TOWER_SCRIPT_NAME=$(basename "$TOWER_SCRIPT_NAME")

# Ensure log directory exists
_ensure_log_dir() {
    mkdir -p "$TOWER_LOG_DIR" 2>/dev/null || true
}

# Log to file (always, not just debug mode)
_log_to_file() {
    local level="$1"
    local msg="$2"
    _ensure_log_dir
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] [$TOWER_SCRIPT_NAME] $msg" >>"$TOWER_LOG_FILE" 2>/dev/null || true
}

# Error trap handler - called when a command fails
_tower_error_trap() {
    local exit_code=$?
    local line_no="${1:-unknown}"
    local command="${BASH_COMMAND:-unknown}"

    # Don't trigger on intentional exits
    [[ "$exit_code" -eq 0 ]] && return 0

    local error_msg="Line $line_no: Command failed (exit $exit_code): $command"

    # Always log errors to file
    _log_to_file "ERROR" "$error_msg"

    if [[ "$TOWER_DEBUG" == "1" ]]; then
        echo "ERROR: [$TOWER_SCRIPT_NAME] $error_msg" >&2
        echo "DEBUG: Stack trace:" >&2
        local frame=0
        while caller $frame; do
            ((frame++)) || true
        done 2>/dev/null >&2
    fi
}

# Set up error trap
trap '_tower_error_trap ${LINENO}' ERR

# Debug logging function
debug_log() {
    local msg="$1"
    _log_to_file "DEBUG" "$msg"
    [[ "$TOWER_DEBUG" != "1" ]] && return 0
    echo "DEBUG: [$TOWER_SCRIPT_NAME] $msg" >&2
}

# Info logging (always to file, optionally to stderr)
info_log() {
    local msg="$1"
    _log_to_file "INFO" "$msg"
}

# Error logging (always to file and stderr)
error_log() {
    local msg="$1"
    _log_to_file "ERROR" "$msg"
    echo "ERROR: [$TOWER_SCRIPT_NAME] $msg" >&2
}

# ============================================================================
# Colors
# ============================================================================
readonly C_RESET="\033[0m"
readonly C_HEADER="\033[1;36m"  # Cyan bold
readonly C_SESSION="\033[1;34m" # Blue bold
readonly C_WINDOW="\033[0;36m"  # Cyan
readonly C_PANE="\033[0;37m"    # Gray
readonly C_ACTIVE="\033[1;32m"  # Green bold
readonly C_GIT="\033[0;33m"     # Yellow
readonly C_GREEN="\033[0;32m"
readonly C_YELLOW="\033[0;33m"
readonly C_BLUE="\033[0;34m"
readonly C_RED="\033[0;31m"
readonly C_DIFF_ADD="\033[0;32m" # Green
readonly C_DIFF_DEL="\033[0;31m" # Red
readonly C_HUNK="\033[0;36m"     # Cyan
readonly C_INFO="\033[0;33m"     # Yellow

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
# ============================================================================
# Socket Separation Configuration
# ============================================================================
# Claude Tower uses TWO dedicated tmux servers, completely separate from
# the user's default tmux server:
#
#   1. Navigator Server (-L claude-tower): Runs the Navigator UI
#   2. Session Server (-L claude-tower-sessions): Runs Claude Code sessions
#
# This architecture provides:
#   - Complete isolation from user's default tmux environment
#   - Navigator can control sessions without interference
#   - Sessions can be managed independently
#   - Clean separation of concerns

# Navigator server socket (control plane)
readonly TOWER_NAV_SOCKET="${CLAUDE_TOWER_NAV_SOCKET:-claude-tower}"
readonly TOWER_NAV_SESSION="navigator"
readonly TOWER_NAV_WIDTH="${CLAUDE_TOWER_NAV_WIDTH:-24}"

# Session server socket (data plane)
readonly TOWER_SESSION_SOCKET="${CLAUDE_TOWER_SESSION_SOCKET:-claude-tower-sessions}"

# State files for cross-server communication
readonly TOWER_NAV_STATE_DIR="/tmp/claude-tower"
readonly TOWER_NAV_SELECTED_FILE="${TOWER_NAV_STATE_DIR}/selected"
readonly TOWER_NAV_CALLER_FILE="${TOWER_NAV_STATE_DIR}/caller"
readonly TOWER_NAV_FOCUS_FILE="${TOWER_NAV_STATE_DIR}/focus"

# tmux wait-for channel for view pane updates
readonly TOWER_VIEW_UPDATE_CHANNEL="tower-view-update"

# ============================================================================
# Navigator Helper Functions
# ============================================================================

# Validate session ID format (security: prevent command injection)
# Arguments:
#   $1 - Session ID to validate
# Returns:
#   0 if valid tower session ID, 1 if invalid
validate_tower_session_id() {
    local session_id="$1"
    [[ "$session_id" =~ ^tower_[a-zA-Z0-9_-]{1,60}$ ]]
}

# Ensure session ID has tower_ prefix and validate
# Security: Validates input before adding prefix to prevent injection
# Arguments:
#   $1 - Session ID (with or without tower_ prefix)
# Returns:
#   Validated session ID with tower_ prefix, or empty string on failure
# Exit:
#   Returns 1 if validation fails
ensure_tower_prefix() {
    local session_id="$1"

    # Remove tower_ prefix if present for validation
    local name="${session_id#tower_}"

    # Sanitize the name part
    name=$(sanitize_name "$name")

    if [[ -z "$name" ]]; then
        error_log "Invalid session ID: empty after sanitization"
        return 1
    fi

    local result="tower_${name}"

    # Final validation
    if ! validate_tower_session_id "$result"; then
        error_log "Invalid session ID format: $result"
        return 1
    fi

    echo "$result"
}

# Ensure Navigator state directory exists with secure permissions
# Security: Creates directory and sets 700 permissions to prevent access by other users
ensure_nav_state_dir() {
    if [[ ! -d "$TOWER_NAV_STATE_DIR" ]]; then
        mkdir -p "$TOWER_NAV_STATE_DIR" 2>/dev/null || true
    fi
    # Set secure permissions (prevents other users from accessing state files)
    chmod 700 "$TOWER_NAV_STATE_DIR" 2>/dev/null || true
}

# Check if Navigator server is running
is_nav_server_running() {
    tmux -L "$TOWER_NAV_SOCKET" list-sessions &>/dev/null
}

# Check if Navigator session exists
is_nav_session_exists() {
    tmux -L "$TOWER_NAV_SOCKET" has-session -t "$TOWER_NAV_SESSION" 2>/dev/null
}

# Run command on Navigator server
nav_tmux() {
    tmux -L "$TOWER_NAV_SOCKET" "$@"
}

# Execute tmux command on SESSION server (for Claude Code sessions)
# This isolates all Claude sessions from the user's default tmux server
session_tmux() {
    TMUX= tmux -L "$TOWER_SESSION_SOCKET" "$@"
}

# Get currently selected session from state file
get_nav_selected() {
    if [[ -f "$TOWER_NAV_SELECTED_FILE" ]]; then
        cat "$TOWER_NAV_SELECTED_FILE" 2>/dev/null || echo ""
    fi
}

# Set currently selected session
set_nav_selected() {
    local session_id="$1"
    ensure_nav_state_dir
    echo "$session_id" >"$TOWER_NAV_SELECTED_FILE"
}

# Get caller session (session to return to on quit)
get_nav_caller() {
    if [[ -f "$TOWER_NAV_CALLER_FILE" ]]; then
        cat "$TOWER_NAV_CALLER_FILE" 2>/dev/null || echo ""
    fi
}

# Set caller session
set_nav_caller() {
    local session_id="$1"
    ensure_nav_state_dir
    echo "$session_id" >"$TOWER_NAV_CALLER_FILE"
}

# Get current focus (list or view)
get_nav_focus() {
    if [[ -f "$TOWER_NAV_FOCUS_FILE" ]]; then
        cat "$TOWER_NAV_FOCUS_FILE" 2>/dev/null || echo "list"
    else
        echo "list"
    fi
}

# Set current focus
set_nav_focus() {
    local focus="$1" # "list" or "view"
    ensure_nav_state_dir
    echo "$focus" >"$TOWER_NAV_FOCUS_FILE"
}

# Clean up Navigator state files
cleanup_nav_state() {
    rm -f "$TOWER_NAV_SELECTED_FILE" "$TOWER_NAV_CALLER_FILE" "$TOWER_NAV_FOCUS_FILE" 2>/dev/null || true
}

# Kill Navigator server
kill_nav_server() {
    if is_nav_server_running; then
        nav_tmux kill-server 2>/dev/null || true
    fi
    cleanup_nav_state
}

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

    # Validate inputs
    [[ -z "$path" || -z "$base" ]] && return 1

    # Normalize paths (handle .., ., and make absolute)
    # Use Python as fallback for macOS which lacks realpath -m
    local resolved_path resolved_base

    # Try GNU realpath -m first (Linux), fall back to manual normalization (macOS)
    if resolved_path=$(realpath -m "$path" 2>/dev/null); then
        resolved_base=$(realpath -m "$base" 2>/dev/null) || return 1
    else
        # macOS fallback: manually normalize path
        # Remove trailing slashes and normalize
        resolved_base="${base%/}"
        # For the path, ensure it's absolute and normalize
        if [[ "$path" == /* ]]; then
            resolved_path="$path"
        else
            resolved_path="$(pwd)/$path"
        fi
        # Remove .. and . components manually
        # Simple check: ensure path doesn't contain .. that could escape
        if [[ "$path" == *".."* ]]; then
            return 1
        fi
        resolved_path="${resolved_path%/}"
    fi

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
#   $2 - (optional) Exit code to return (default: does not exit)
handle_error() {
    local msg="$1"
    local exit_code="${2:-}"
    local formatted_msg="${C_RED}Error:${C_RESET} $msg"

    # Always log to file
    _log_to_file "ERROR" "$msg"

    echo -e "$formatted_msg" >&2

    # Skip tmux display-message if TOWER_QUIET_ERRORS is set
    # (Navigator UI handles error display itself)
    if [[ -z "${TOWER_QUIET_ERRORS:-}" ]]; then
        tmux display-message "❌ Error: $msg" 2>/dev/null || true
    fi

    if [[ -n "$exit_code" ]]; then
        exit "$exit_code"
    fi
}

# Display warning message to user via tmux
# Arguments:
#   $1 - Warning message
handle_warning() {
    local msg="$1"
    local formatted_msg="${C_YELLOW}Warning:${C_RESET} $msg"

    _log_to_file "WARN" "$msg"

    echo -e "$formatted_msg" >&2
    tmux display-message "⚠️ Warning: $msg" 2>/dev/null || true
}

# Display info message to user via tmux
# Arguments:
#   $1 - Info message
handle_info() {
    local msg="$1"
    _log_to_file "INFO" "$msg"
    tmux display-message "$msg" 2>/dev/null || true
}

# Display success message
# Arguments:
#   $1 - Success message
handle_success() {
    local msg="$1"
    local formatted_msg="${C_GREEN}Success:${C_RESET} $msg"

    _log_to_file "INFO" "Success: $msg"

    echo -e "$formatted_msg"
    tmux display-message "✓ $msg" 2>/dev/null || true
}

# Graceful error exit with cleanup hint
# Arguments:
#   $1 - Error message
#   $2 - Exit code (default: 1)
die() {
    local msg="$1"
    local exit_code="${2:-1}"

    handle_error "$msg"

    if [[ "$TOWER_DEBUG" == "1" ]]; then
        echo "DEBUG: Exiting with code $exit_code from ${FUNCNAME[1]:-main}" >&2
    fi

    exit "$exit_code"
}

# ============================================================================
# Dependency Checks
# ============================================================================

# Installation hints for common missing dependencies
declare -A INSTALL_HINTS=(
    [fzf]="Install fzf: https://github.com/junegunn/fzf#installation"
    [git]="Install git: apt install git / brew install git"
    [tmux]="Install tmux: apt install tmux / brew install tmux"
    [claude]="Install Claude Code: https://docs.anthropic.com/en/docs/claude-code"
    [realpath]="Install coreutils: apt install coreutils / brew install coreutils"
)

# Check if required command is available
# Arguments:
#   $1 - Command name
# Returns:
#   0 if available, 1 if not
require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        local hint="${INSTALL_HINTS[$cmd]:-}"
        local msg="'$cmd' is required but not installed"
        [[ -n "$hint" ]] && msg="$msg. $hint"
        handle_error "$msg"
        return 1
    fi
    debug_log "Dependency check passed: $cmd"
    return 0
}

# Check all required dependencies at once
# Returns:
#   0 if all available, 1 if any missing
require_all_dependencies() {
    local missing=()

    for cmd in git tmux; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        handle_error "Missing required dependencies: ${missing[*]}"
        for cmd in "${missing[@]}"; do
            local hint="${INSTALL_HINTS[$cmd]:-}"
            [[ -n "$hint" ]] && echo "  - $hint" >&2
        done
        return 1
    fi

    return 0
}

# ============================================================================
# Confirmation Dialog
# ============================================================================

# Show confirmation dialog using tmux display-menu
# Arguments:
#   $1 - Message to display
# Returns:
#   0 if confirmed (Yes), 1 if declined (No) or error
confirm() {
    local msg="$1"
    local result_file
    result_file=$(mktemp)

    # Use tmux display-menu for confirmation
    tmux display-menu -T "$msg" \
        "Yes" y "run-shell 'echo yes > $result_file'" \
        "No" n "run-shell 'echo no > $result_file'" \
        2>/dev/null

    # Wait briefly for menu result
    sleep 0.2

    local result
    result=$(cat "$result_file" 2>/dev/null || echo "no")
    rm -f "$result_file"

    [[ "$result" == "yes" ]]
}

# ============================================================================
# Metadata Management
# ============================================================================
# Metadata is stored as simple key=value files for each session.
# This allows recovery of session info even if tmux session options are lost.

# Ensure metadata directory exists with secure permissions
ensure_metadata_dir() {
    if [[ ! -d "$TOWER_METADATA_DIR" ]]; then
        mkdir -p "$TOWER_METADATA_DIR" 2>/dev/null || true
        chmod 700 "$TOWER_METADATA_DIR" 2>/dev/null || true
    fi
}

# Save session metadata to file
# Arguments:
#   $1 - Session ID (with tower_ prefix)
#   $2 - Directory path
save_metadata() {
    local session_id="$1"
    local directory_path="$2"

    ensure_metadata_dir

    local metadata_file="${TOWER_METADATA_DIR}/${session_id}.meta"
    local session_name="${session_id#tower_}"

    {
        echo "session_id=${session_id}"
        echo "session_name=${session_name}"
        echo "directory_path=${directory_path}"
        echo "created_at=$(date -Iseconds)"
    } >"$metadata_file"
}

# Load session metadata from file
# Arguments:
#   $1 - Session ID
# Returns:
#   Exports variables: META_SESSION_NAME, META_DIRECTORY_PATH, META_CREATED_AT
load_metadata() {
    local session_id="$1"
    local metadata_file="${TOWER_METADATA_DIR}/${session_id}.meta"

    # Initialize with empty values
    META_SESSION_NAME=""
    META_DIRECTORY_PATH=""
    META_CREATED_AT=""

    if [[ -f "$metadata_file" ]]; then
        while IFS='=' read -r key value; do
            case "$key" in
                # v2 fields
                session_name) META_SESSION_NAME="$value" ;;
                directory_path) META_DIRECTORY_PATH="$value" ;;
                created_at) META_CREATED_AT="$value" ;;

                # v1 backwards compatibility
                worktree_path)
                    # Use worktree_path as directory_path if not already set
                    [[ -z "$META_DIRECTORY_PATH" ]] && META_DIRECTORY_PATH="$value"
                    ;;
                repository_path | repo_path)
                    # Use repository_path as fallback for directory_path
                    [[ -z "$META_DIRECTORY_PATH" ]] && META_DIRECTORY_PATH="$value"
                    ;;
            esac
        done <"$metadata_file"

        # Derive session_name from session_id if not in metadata
        if [[ -z "$META_SESSION_NAME" ]]; then
            META_SESSION_NAME="${session_id#tower_}"
        fi

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
# Orphaned Metadata Detection and Cleanup
# ============================================================================
# Orphaned metadata files are metadata that exist but have no corresponding
# active tmux session. These can occur when sessions are terminated
# unexpectedly.

# Get list of active tmux sessions from session server
get_active_sessions() {
    session_tmux list-sessions -F '#{session_name}' 2>/dev/null || true
}

# Find orphaned metadata (metadata without active sessions)
# Returns:
#   List of orphaned session IDs
find_orphaned_metadata() {
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

# Remove orphaned metadata
# Arguments:
#   $1 - Session ID
# Returns:
#   0 on success, 1 on failure
remove_orphaned_metadata() {
    local session_id="$1"

    # Just delete metadata (no directory cleanup)
    delete_metadata "$session_id"
    return 0
}

# ============================================================================
# Safe Command Execution
# ============================================================================
# Wrappers for commands that might fail, with proper error handling

# Safe tmux command execution with error handling
# Arguments:
#   $@ - tmux command and arguments
# Returns:
#   0 on success, 1 on failure
safe_tmux() {
    local cmd="$1"
    shift

    debug_log "Executing: tmux $cmd $*"

    if ! tmux "$cmd" "$@" 2>/dev/null; then
        debug_log "tmux command failed: $cmd $*"
        return 1
    fi
    return 0
}

# Safe git command execution with error handling
# Arguments:
#   $@ - git command and arguments
# Returns:
#   0 on success, 1 on failure
safe_git() {
    local cmd="$1"
    shift

    debug_log "Executing: git $cmd $*"

    if ! git "$cmd" "$@" 2>/dev/null; then
        debug_log "git command failed: $cmd $*"
        return 1
    fi
    return 0
}

# Execute command with timeout
# Arguments:
#   $1 - Timeout in seconds
#   $@ - Command to execute
# Returns:
#   Command exit code or 124 on timeout
run_with_timeout() {
    local timeout="$1"
    shift

    if command -v timeout &>/dev/null; then
        timeout "$timeout" "$@"
    else
        # Fallback if timeout command not available
        "$@"
    fi
}

# ============================================================================
# Loading Spinner
# ============================================================================
# Visual feedback for long-running operations

# Spinner characters for animation
readonly SPINNER_CHARS="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

# Global variable to track spinner process
SPINNER_PID=""

# Start spinner in background
# Arguments:
#   $1 - Message to display
start_spinner() {
    local msg="${1:-Processing...}"

    # Don't start if already running
    [[ -n "$SPINNER_PID" ]] && return 0

    # Show initial message in tmux status
    tmux display-message "⏳ $msg" 2>/dev/null || true

    # Start background spinner process
    (
        local i=0
        local chars_len=${#SPINNER_CHARS}
        while true; do
            local char="${SPINNER_CHARS:i%chars_len:1}"
            printf "\r%s %s " "$char" "$msg" >&2
            ((i++)) || true
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null || true

    debug_log "Started spinner (PID: $SPINNER_PID) with message: $msg"
}

# Stop spinner and show result
# Arguments:
#   $1 - Exit status (0 for success, non-zero for error)
#   $2 - Success message (optional)
#   $3 - Error message (optional)
stop_spinner() {
    local status="${1:-0}"
    local success_msg="${2:-Done}"
    local error_msg="${3:-Failed}"

    # Kill spinner process if running
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""
        # Clear the spinner line
        printf "\r\033[K" >&2
    fi

    debug_log "Stopped spinner with status: $status"

    if [[ "$status" -eq 0 ]]; then
        printf "%b✓ %s%b\n" "$C_GREEN" "$success_msg" "$C_RESET" >&2
        tmux display-message "✓ $success_msg" 2>/dev/null || true
    else
        printf "%b✗ %s%b\n" "$C_RED" "$error_msg" "$C_RESET" >&2
        tmux display-message "✗ $error_msg" 2>/dev/null || true
    fi
}

# Execute command with spinner
# Arguments:
#   $1 - Message to display during execution
#   $2... - Command and arguments to execute
# Returns:
#   Command exit code
with_spinner() {
    local msg="$1"
    shift

    start_spinner "$msg"

    local output exit_code
    output=$("$@" 2>&1)
    exit_code=$?

    stop_spinner "$exit_code" "$msg" "$msg failed"

    # Output the command output if any
    [[ -n "$output" ]] && echo "$output"

    return "$exit_code"
}

# Cleanup spinner on script exit
_cleanup_spinner() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        printf "\r\033[K" >&2
    fi
}
trap _cleanup_spinner EXIT

# ============================================================================
# Validation Helpers
# ============================================================================

# Validate session name format
# Arguments:
#   $1 - Session name to validate
# Returns:
#   0 if valid, 1 if invalid
validate_session_name() {
    local name="$1"

    # Must not be empty
    if [[ -z "$name" ]]; then
        debug_log "Session name is empty"
        return 1
    fi

    # Must not exceed max length
    if [[ ${#name} -gt 64 ]]; then
        debug_log "Session name too long: ${#name} > 64"
        return 1
    fi

    # Must contain only allowed characters
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        debug_log "Session name contains invalid characters: $name"
        return 1
    fi

    return 0
}

# Check if session exists on default server
# Arguments:
#   $1 - Session ID
# Returns:
#   0 if exists, 1 if not
session_exists() {
    local session_id="$1"
    session_tmux has-session -t "$session_id" 2>/dev/null
}


# ============================================================================
# Session State Detection (v3.0 - Idempotent)
# ============================================================================
# Session states (simplified for idempotency):
#   Active (▶)  - tmux session exists
#   Dormant (○) - Metadata exists but no tmux session
#
# Note: "exited" state was removed. If tmux session exists, it's active.
# Claude's running state is an internal detail, not Navigator's concern.

readonly STATE_ACTIVE="active"
readonly STATE_DORMANT="dormant"

readonly ICON_STATE_ACTIVE="▶"
readonly ICON_STATE_DORMANT="○"

# Get session state (always checks default server)
# Arguments:
#   $1 - Session ID (with tower_ prefix)
# Returns:
#   State string: active or dormant (empty if not exists)
# Idempotent: Uses has-session for reliable existence check
get_session_state() {
    local session_id="$1"

    # Check if tmux session exists using has-session (most reliable)
    if session_tmux has-session -t "$session_id" 2>/dev/null; then
        echo "$STATE_ACTIVE"
        return 0
    fi

    # Session doesn't exist - check if metadata exists (Dormant)
    if has_metadata "$session_id"; then
        echo "$STATE_DORMANT"
        return 0
    fi

    # Neither session nor metadata exists
    return 0
}

# Get state icon
# Arguments:
#   $1 - State string
# Returns:
#   Icon character
get_state_icon() {
    local state="$1"
    case "$state" in
        "$STATE_ACTIVE") echo "$ICON_STATE_ACTIVE" ;;
        "$STATE_DORMANT") echo "$ICON_STATE_DORMANT" ;;
        *) echo "?" ;;
    esac
}

# ============================================================================
# Session List (v2.0)
# ============================================================================

# List all tower sessions (active + dormant) - OPTIMIZED
# Output format: session_id:state
# Uses single tmux call for all active sessions
list_all_sessions() {
    local -A active_sessions=()

    # Get all tower sessions in ONE tmux call
    while IFS=$'\t' read -r session_id _; do
        [[ -z "$session_id" ]] && continue
        [[ "$session_id" != tower_* ]] && continue

        active_sessions["$session_id"]=1

        # tmux session exists = active (simplified, idempotent)
        local state="$STATE_ACTIVE"

        echo "${session_id}:${state}"
    done < <(session_tmux list-sessions -F '#{session_name}' 2>/dev/null || true)

    # Check metadata for dormant sessions
    for meta_file in "${TOWER_METADATA_DIR}"/*.meta; do
        [[ -f "$meta_file" ]] || continue

        local session_id
        session_id=$(basename "$meta_file" .meta)

        # Skip if already processed (active session)
        [[ -n "${active_sessions[$session_id]:-}" ]] && continue

        # This is a dormant session
        echo "${session_id}:${STATE_DORMANT}"
    done
}

# Output session info in standard format (optimized - no git calls)
# Arguments:
#   $1 - Session ID
# Output: session_id:state
_output_session_info() {
    local session_id="$1"
    local state

    state=$(get_session_state "$session_id")

    echo "${session_id}:${state}"
}

# ============================================================================
# Session Operations (v2.0)
# ============================================================================

# Create a new session
# Arguments:
#   $1 - Session name (without tower_ prefix)
#   $2 - Type: ignored (for backwards compatibility)
#   $3 - Working directory
# Returns:
#   0 on success, 1 on failure
create_session() {
    local name="$1"
    local _type="$2"  # Ignored, kept for backwards compatibility
    local directory_path="$3"

    # Sanitize and validate name
    local sanitized_name
    sanitized_name=$(sanitize_name "$name")
    if ! validate_session_name "$sanitized_name"; then
        handle_error "Invalid session name: $name"
        return 1
    fi

    local session_id
    session_id=$(normalize_session_name "$sanitized_name")

    # Check if session already exists
    if session_exists "$session_id"; then
        handle_error "Session already exists: $sanitized_name"
        return 1
    fi

    # Validate directory
    if [[ ! -d "$directory_path" ]]; then
        handle_error "Directory does not exist: $directory_path"
        return 1
    fi

    # Save metadata
    save_metadata "$session_id" "$directory_path"

    # Create tmux session and start Claude
    _start_session_with_claude "$session_id" "$directory_path"
}


# Wait for shell prompt to be ready in a pane
# Uses tmux capture-pane to check for prompt characters
_wait_for_shell_ready() {
    local session_id="$1"
    local max_attempts=30  # 3 seconds max (30 * 0.1s)
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        # Capture pane content and check for common prompt indicators
        local content
        content=$(session_tmux capture-pane -t "$session_id" -p 2>/dev/null || echo "")

        # Check for prompt characters: $, >, ❯, %, #
        if [[ "$content" =~ [\$\>❯%#][[:space:]]*$ ]]; then
            debug_log "Shell ready after $attempt attempts"
            return 0
        fi

        sleep 0.1
        ((attempt++)) || true  # Prevent exit on attempt=0 (returns 1 with set -e)
    done

    # Timeout - proceed anyway but log warning
    debug_log "Shell readiness timeout after $max_attempts attempts"
    return 0
}

# Start tmux session with Claude (internal)
# Start a tmux session with Claude on the SESSION server
# This isolates Claude sessions from the user's default tmux server
_start_session_with_claude() {
    local session_id="$1"
    local working_dir="$2"
    local continue_flag="${3:-}"

    # Create detached tmux session on SESSION server (isolated from user's default)
    session_tmux new-session -d -s "$session_id" -c "$working_dir"

    # Wait for shell prompt to be ready before sending keys
    _wait_for_shell_ready "$session_id"

    # Clear screen first to flush any terminal initialization noise
    session_tmux send-keys -t "$session_id" C-l

    # Wait for clear to complete
    _wait_for_shell_ready "$session_id"

    # Start Claude
    local claude_cmd="$TOWER_PROGRAM"
    [[ -n "$continue_flag" ]] && claude_cmd="$TOWER_PROGRAM --continue"

    # Use C-m (Ctrl-M) instead of Enter for more reliable key sending
    session_tmux send-keys -t "$session_id" "$claude_cmd" C-m

    handle_success "Session created: ${session_id#tower_}"
}

# Restore a dormant session
# Arguments:
#   $1 - Session ID
# Returns:
#   0 on success, 1 on failure
restore_session() {
    local session_id="$1"

    # Check if session is dormant
    local state
    state=$(get_session_state "$session_id")

    if [[ "$state" != "$STATE_DORMANT" ]]; then
        if [[ "$state" == "" ]]; then
            handle_error "Session does not exist: ${session_id#tower_}"
        else
            handle_info "Session is already active: ${session_id#tower_}"
        fi
        return 1
    fi

    # Load metadata
    if ! load_metadata "$session_id"; then
        handle_error "Cannot load session metadata: ${session_id#tower_}"
        return 1
    fi

    # Get directory path from metadata
    local working_dir="$META_DIRECTORY_PATH"

    # Fallback to home directory if not found
    if [[ -z "$working_dir" || ! -d "$working_dir" ]]; then
        handle_warning "Directory not found: $working_dir, using HOME"
        working_dir="$HOME"
    fi

    # Create tmux session and start Claude with --continue
    _start_session_with_claude "$session_id" "$working_dir" "continue"
}

# Delete a session
# Arguments:
#   $1 - Session ID
#   $2 - Force flag (optional, "force" to skip confirmation)
# Returns:
#   0 on success, 1 on failure
delete_session() {
    local session_id="$1"
    local force="${2:-}"

    local state
    state=$(get_session_state "$session_id")

    if [[ -z "$state" ]]; then
        handle_error "Session does not exist: ${session_id#tower_}"
        return 1
    fi

    # Confirmation (unless forced)
    if [[ "$force" != "force" && "$force" != "-f" ]]; then
        local msg="Delete session '${session_id#tower_}'?"
        if ! confirm "$msg"; then
            handle_info "Cancelled"
            return 1
        fi
    fi

    # Kill tmux session if active (on session server)
    if [[ "$state" != "$STATE_DORMANT" ]]; then
        session_tmux kill-session -t "$session_id" 2>/dev/null || true
    fi

    # Delete metadata (directory is NOT deleted)
    delete_metadata "$session_id"

    handle_success "Session deleted: ${session_id#tower_}"
}

# Restart Claude in a session
# Arguments:
#   $1 - Session ID
# Returns:
#   0 on success, 1 on failure
restart_session() {
    local session_id="$1"

    local state
    state=$(get_session_state "$session_id")

    if [[ "$state" == "$STATE_DORMANT" ]]; then
        # Restore dormant session
        restore_session "$session_id"
        return $?
    fi

    if [[ -z "$state" ]]; then
        handle_error "Session does not exist: ${session_id#tower_}"
        return 1
    fi

    # Kill current process and start Claude again (on session server)
    session_tmux send-keys -t "$session_id" C-c 2>/dev/null || true
    sleep 0.5

    # Always use --continue for persistent sessions
    local claude_cmd="$TOWER_PROGRAM --continue"
    session_tmux send-keys -t "$session_id" "$claude_cmd" C-m

    handle_success "Session restarted: ${session_id#tower_}"
}

# Send input to a session
# Arguments:
#   $1 - Session ID
#   $2 - Input text
# Returns:
#   0 on success, 1 on failure
send_to_session() {
    local session_id="$1"
    local input="$2"

    local state
    state=$(get_session_state "$session_id")

    if [[ "$state" == "$STATE_DORMANT" || -z "$state" ]]; then
        handle_error "Session is not active: ${session_id#tower_}"
        return 1
    fi

    session_tmux send-keys -t "$session_id" "$input" C-m
}

# ============================================================================
# Auto-restore dormant sessions
# ============================================================================

# Restore all dormant worktree sessions
restore_all_dormant() {
    local restored=0
    local failed=0

    for meta_file in "${TOWER_METADATA_DIR}"/*.meta; do
        [[ -f "$meta_file" ]] || continue

        local session_id
        session_id=$(basename "$meta_file" .meta)

        local state
        state=$(get_session_state "$session_id")

        if [[ "$state" == "$STATE_DORMANT" ]]; then
            if restore_session "$session_id" 2>/dev/null; then
                ((restored++)) || true
            else
                ((failed++)) || true
            fi
        fi
    done

    if [[ $restored -gt 0 || $failed -gt 0 ]]; then
        handle_info "Restored $restored session(s), $failed failed"
    fi
}
