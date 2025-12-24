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

# Store the calling script name for error messages
TOWER_SCRIPT_NAME="${TOWER_SCRIPT_NAME:-${BASH_SOURCE[1]:-unknown}}"
TOWER_SCRIPT_NAME=$(basename "$TOWER_SCRIPT_NAME")

# Error trap handler - called when a command fails
_tower_error_trap() {
    local exit_code=$?
    local line_no="${1:-unknown}"
    local command="${BASH_COMMAND:-unknown}"

    # Don't trigger on intentional exits
    [[ "$exit_code" -eq 0 ]] && return 0

    local error_msg="[$TOWER_SCRIPT_NAME:$line_no] Command failed (exit $exit_code): $command"

    if [[ "$TOWER_DEBUG" == "1" ]]; then
        echo "DEBUG: $error_msg" >&2
        echo "DEBUG: Stack trace:" >&2
        local frame=0
        while caller $frame; do
            ((frame++))
        done 2>/dev/null >&2
    fi

    # Log to file if debug enabled
    if [[ "$TOWER_DEBUG" == "1" ]]; then
        local log_file="${CLAUDE_TOWER_METADATA_DIR:-$HOME/.claude-tower/metadata}/tower.log"
        mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
        echo "[$(date -Iseconds)] $error_msg" >> "$log_file" 2>/dev/null || true
    fi
}

# Set up error trap
trap '_tower_error_trap ${LINENO}' ERR

# Debug logging function
debug_log() {
    [[ "$TOWER_DEBUG" != "1" ]] && return 0
    local msg="$1"
    echo "DEBUG: [$TOWER_SCRIPT_NAME] $msg" >&2
}

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

    echo -e "$formatted_msg" >&2
    tmux display-message "Error: $msg" 2>/dev/null || true

    debug_log "Error occurred: $msg"

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

    echo -e "$formatted_msg" >&2
    tmux display-message "Warning: $msg" 2>/dev/null || true

    debug_log "Warning: $msg"
}

# Display info message to user via tmux
# Arguments:
#   $1 - Info message
handle_info() {
    local msg="$1"
    tmux display-message "$msg" 2>/dev/null || true
    debug_log "Info: $msg"
}

# Display success message
# Arguments:
#   $1 - Success message
handle_success() {
    local msg="$1"
    local formatted_msg="${C_GREEN}Success:${C_RESET} $msg"

    echo -e "$formatted_msg"
    tmux display-message "$msg" 2>/dev/null || true

    debug_log "Success: $msg"
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
        "No"  n "run-shell 'echo no > $result_file'" \
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
            ((i++))
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

# Check if session exists
# Arguments:
#   $1 - Session ID
# Returns:
#   0 if exists, 1 if not
session_exists() {
    local session_id="$1"
    tmux has-session -t "$session_id" 2>/dev/null
}

# Check if worktree exists
# Arguments:
#   $1 - Worktree path
# Returns:
#   0 if exists, 1 if not
worktree_exists() {
    local path="$1"
    [[ -d "$path" ]] && [[ -f "$path/.git" || -d "$path/.git" ]]
}

# ============================================================================
# Session State Detection (v2.0)
# ============================================================================
# Session states:
#   Running (◉) - Claude is actively outputting
#   Idle (▶)    - Claude is waiting for input
#   Exited (!)  - Claude process has exited
#   Dormant (○) - Metadata exists but no tmux session

readonly STATE_RUNNING="running"
readonly STATE_IDLE="idle"
readonly STATE_EXITED="exited"
readonly STATE_DORMANT="dormant"

readonly ICON_STATE_RUNNING="◉"
readonly ICON_STATE_IDLE="▶"
readonly ICON_STATE_EXITED="!"
readonly ICON_STATE_DORMANT="○"

readonly TYPE_WORKTREE="worktree"
readonly TYPE_SIMPLE="simple"

readonly ICON_TYPE_WORKTREE="[W]"
readonly ICON_TYPE_SIMPLE="[S]"

# Get session state
# Arguments:
#   $1 - Session ID (with tower_ prefix)
# Returns:
#   State string: running, idle, exited, or dormant
get_session_state() {
    local session_id="$1"

    # Check if tmux session exists
    if ! tmux has-session -t "$session_id" 2>/dev/null; then
        # No tmux session - check if metadata exists (Dormant)
        if has_metadata "$session_id"; then
            echo "$STATE_DORMANT"
        else
            echo ""  # Session doesn't exist at all
        fi
        return 0
    fi

    # tmux session exists - check Claude process
    local pane_cmd
    pane_cmd=$(tmux display-message -t "$session_id" -p '#{pane_current_command}' 2>/dev/null || echo "")

    # Check if Claude (or configured program) is running
    local program_name
    program_name=$(basename "$TOWER_PROGRAM")

    if [[ "$pane_cmd" != "$program_name" && "$pane_cmd" != "claude" ]]; then
        echo "$STATE_EXITED"
        return 0
    fi

    # Claude is running - check if actively outputting or idle
    # We use a simple heuristic: capture pane content and check last line
    local last_lines
    last_lines=$(tmux capture-pane -t "$session_id" -p -S -5 2>/dev/null | tail -5 || echo "")

    # Common idle patterns in Claude Code
    if echo "$last_lines" | grep -qE '^\s*>\s*$|^\s*claude>\s*$|^\s*\$\s*$|What would you like|waiting for input|Ready'; then
        echo "$STATE_IDLE"
    else
        echo "$STATE_RUNNING"
    fi
}

# Get state icon
# Arguments:
#   $1 - State string
# Returns:
#   Icon character
get_state_icon() {
    local state="$1"
    case "$state" in
        "$STATE_RUNNING") echo "$ICON_STATE_RUNNING" ;;
        "$STATE_IDLE")    echo "$ICON_STATE_IDLE" ;;
        "$STATE_EXITED")  echo "$ICON_STATE_EXITED" ;;
        "$STATE_DORMANT") echo "$ICON_STATE_DORMANT" ;;
        *)                echo "?" ;;
    esac
}

# Get session type
# Arguments:
#   $1 - Session ID
# Returns:
#   Type string: worktree or simple
get_session_type() {
    local session_id="$1"

    if load_metadata "$session_id" 2>/dev/null; then
        if [[ "$META_SESSION_TYPE" == "workspace" || "$META_SESSION_TYPE" == "worktree" ]]; then
            echo "$TYPE_WORKTREE"
        else
            echo "$TYPE_SIMPLE"
        fi
    else
        echo "$TYPE_SIMPLE"
    fi
}

# Get type icon
# Arguments:
#   $1 - Type string
# Returns:
#   Icon string
get_type_icon() {
    local type="$1"
    case "$type" in
        "$TYPE_WORKTREE") echo "$ICON_TYPE_WORKTREE" ;;
        "$TYPE_SIMPLE")   echo "$ICON_TYPE_SIMPLE" ;;
        *)                echo "[?]" ;;
    esac
}

# ============================================================================
# Session List (v2.0)
# ============================================================================

# List all tower sessions (active + dormant)
# Output format: session_id:state:type:display_name:branch:diff_stats
list_all_sessions() {
    local seen_sessions=()

    # First, get all active tmux sessions with tower_ prefix
    while IFS= read -r session_id; do
        [[ -z "$session_id" ]] && continue
        [[ "$session_id" != tower_* ]] && continue

        seen_sessions+=("$session_id")
        _output_session_info "$session_id"
    done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)

    # Then, check metadata for dormant sessions
    for meta_file in "${TOWER_METADATA_DIR}"/*.meta; do
        [[ -f "$meta_file" ]] || continue

        local session_id
        session_id=$(basename "$meta_file" .meta)

        # Skip if already processed (active session)
        local already_seen=false
        for seen in "${seen_sessions[@]}"; do
            if [[ "$seen" == "$session_id" ]]; then
                already_seen=true
                break
            fi
        done
        [[ "$already_seen" == "true" ]] && continue

        # This is a dormant session
        _output_session_info "$session_id"
    done
}

# Output session info in standard format
# Arguments:
#   $1 - Session ID
# Output: session_id:state:type:display_name:branch:diff_stats
_output_session_info() {
    local session_id="$1"
    local state type display_name branch diff_stats working_dir repo_name

    state=$(get_session_state "$session_id")
    type=$(get_session_type "$session_id")
    display_name="${session_id#tower_}"
    branch=""
    diff_stats=""
    repo_name=""

    # Get working directory
    if [[ "$state" != "$STATE_DORMANT" ]]; then
        working_dir=$(tmux display-message -t "$session_id" -p '#{pane_current_path}' 2>/dev/null || echo "")
    else
        # For dormant sessions, use metadata
        if load_metadata "$session_id" 2>/dev/null; then
            working_dir="$META_WORKTREE_PATH"
        fi
    fi

    # Get git info if in a git repo
    if [[ -n "$working_dir" && -d "$working_dir" ]]; then
        if git -C "$working_dir" rev-parse --git-dir &>/dev/null; then
            branch=$(git -C "$working_dir" branch --show-current 2>/dev/null || echo "detached")

            # Get repo name from path
            repo_name=$(basename "$(git -C "$working_dir" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")

            # Get diff stats (staged + unstaged)
            local stats
            stats=$(git -C "$working_dir" diff --numstat 2>/dev/null | \
                awk '{add+=$1; del+=$2} END {if(add>0||del>0) printf "+%d,-%d", add, del}')
            [[ -n "$stats" ]] && diff_stats="$stats"

            # Check for uncommitted changes marker
            if [[ -z "$diff_stats" ]] && ! git -C "$working_dir" diff --quiet 2>/dev/null; then
                diff_stats="*"
            fi
        fi
    fi

    # Format display name with repo if available
    if [[ -n "$repo_name" && "$repo_name" != "$display_name" ]]; then
        display_name="${repo_name}/${display_name}"
    fi

    echo "${session_id}:${state}:${type}:${display_name}:${branch}:${diff_stats}"
}

# ============================================================================
# Session Operations (v2.0)
# ============================================================================

# Create a new session
# Arguments:
#   $1 - Session name (without tower_ prefix)
#   $2 - Type: worktree or simple
#   $3 - Working directory (for simple) or source repo (for worktree)
# Returns:
#   0 on success, 1 on failure
create_session() {
    local name="$1"
    local type="$2"
    local dir="$3"

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

    if [[ "$type" == "$TYPE_WORKTREE" ]]; then
        _create_worktree_session "$session_id" "$sanitized_name" "$dir"
    else
        _create_simple_session "$session_id" "$sanitized_name" "$dir"
    fi
}

# Create worktree session (internal)
_create_worktree_session() {
    local session_id="$1"
    local name="$2"
    local repo_path="$3"

    # Validate repo path
    if [[ ! -d "$repo_path" ]] || ! git -C "$repo_path" rev-parse --git-dir &>/dev/null; then
        handle_error "Not a git repository: $repo_path"
        return 1
    fi

    local worktree_path="${TOWER_WORKTREE_DIR}/${name}"
    local branch_name="tower/${name}"
    local source_commit
    source_commit=$(git -C "$repo_path" rev-parse HEAD 2>/dev/null)

    # Create worktree directory
    mkdir -p "$TOWER_WORKTREE_DIR"

    # Create git worktree with new branch
    if ! git -C "$repo_path" worktree add -b "$branch_name" "$worktree_path" 2>/dev/null; then
        # Branch might exist, try without -b
        if ! git -C "$repo_path" worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
            handle_error "Failed to create worktree"
            return 1
        fi
    fi

    # Save metadata
    save_metadata "$session_id" "worktree" "$repo_path" "$source_commit"

    # Update metadata with additional fields
    local metadata_file="${TOWER_METADATA_DIR}/${session_id}.meta"
    echo "session_name=${name}" >> "$metadata_file"
    echo "branch_name=${branch_name}" >> "$metadata_file"
    echo "repository_name=$(basename "$repo_path")" >> "$metadata_file"

    # Create tmux session and start Claude
    _start_session_with_claude "$session_id" "$worktree_path"
}

# Create simple session (internal)
_create_simple_session() {
    local session_id="$1"
    local name="$2"
    local working_dir="${3:-$(pwd)}"

    # Validate directory
    if [[ ! -d "$working_dir" ]]; then
        handle_error "Directory does not exist: $working_dir"
        return 1
    fi

    # Simple sessions don't save metadata (volatile)
    # Just create tmux session and start Claude
    _start_session_with_claude "$session_id" "$working_dir"
}

# Start tmux session with Claude (internal)
_start_session_with_claude() {
    local session_id="$1"
    local working_dir="$2"
    local continue_flag="${3:-}"

    # Create detached tmux session
    tmux new-session -d -s "$session_id" -c "$working_dir"

    # Start Claude
    local claude_cmd="$TOWER_PROGRAM"
    [[ -n "$continue_flag" ]] && claude_cmd="$TOWER_PROGRAM --continue"

    tmux send-keys -t "$session_id" "$claude_cmd" Enter

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

    local working_dir="$META_WORKTREE_PATH"

    if [[ ! -d "$working_dir" ]]; then
        handle_error "Worktree directory not found: $working_dir"
        return 1
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

    local state type
    state=$(get_session_state "$session_id")
    type=$(get_session_type "$session_id")

    if [[ -z "$state" ]]; then
        handle_error "Session does not exist: ${session_id#tower_}"
        return 1
    fi

    # Confirmation (unless forced)
    if [[ "$force" != "force" ]]; then
        local msg="Delete session '${session_id#tower_}'?"
        [[ "$type" == "$TYPE_WORKTREE" ]] && msg="$msg (includes worktree and branch)"
        if ! confirm "$msg"; then
            handle_info "Cancelled"
            return 1
        fi
    fi

    # Kill tmux session if active
    if [[ "$state" != "$STATE_DORMANT" ]]; then
        tmux kill-session -t "$session_id" 2>/dev/null || true
    fi

    # For worktree sessions, cleanup worktree and branch
    if [[ "$type" == "$TYPE_WORKTREE" ]]; then
        if load_metadata "$session_id" 2>/dev/null; then
            local worktree_path="$META_WORKTREE_PATH"
            local repo_path="$META_REPOSITORY_PATH"

            # Read branch name from metadata
            local branch_name=""
            local metadata_file="${TOWER_METADATA_DIR}/${session_id}.meta"
            if [[ -f "$metadata_file" ]]; then
                branch_name=$(grep "^branch_name=" "$metadata_file" 2>/dev/null | cut -d= -f2)
            fi

            # Remove worktree
            if [[ -d "$worktree_path" ]] && validate_path_within "$worktree_path" "$TOWER_WORKTREE_DIR"; then
                if [[ -n "$repo_path" && -d "$repo_path" ]]; then
                    git -C "$repo_path" worktree remove "$worktree_path" 2>/dev/null || \
                    git -C "$repo_path" worktree remove --force "$worktree_path" 2>/dev/null || \
                    rm -rf "$worktree_path"
                else
                    rm -rf "$worktree_path"
                fi
            fi

            # Delete branch (only if not pushed to remote)
            if [[ -n "$branch_name" && -n "$repo_path" && -d "$repo_path" ]]; then
                # Check if branch exists on remote
                if ! git -C "$repo_path" ls-remote --exit-code --heads origin "$branch_name" &>/dev/null; then
                    git -C "$repo_path" branch -D "$branch_name" 2>/dev/null || true
                fi
            fi
        fi
    fi

    # Delete metadata
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

    # Kill current process and start Claude again
    tmux send-keys -t "$session_id" C-c 2>/dev/null || true
    sleep 0.5

    local type
    type=$(get_session_type "$session_id")

    local claude_cmd="$TOWER_PROGRAM"
    [[ "$type" == "$TYPE_WORKTREE" ]] && claude_cmd="$TOWER_PROGRAM --continue"

    tmux send-keys -t "$session_id" "$claude_cmd" Enter

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

    tmux send-keys -t "$session_id" "$input" Enter
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
