#!/usr/bin/env bash
# error-recovery.sh - Error handling and recovery utilities for Navigator TUI
#
# This library provides:
#   - Safe command execution wrappers (try_command, try_with_retry)
#   - TUI error display components (show_tui_error)
#   - Main loop recovery wrapper (run_with_recovery)
#   - Graceful exit handling (return_to_caller)
#
# Design principle: Navigator should NEVER crash to terminal.
# All errors should be displayed within the TUI and offer recovery options.

# Include guard - prevent multiple sourcing
[[ -n "${_TOWER_ERROR_RECOVERY_LOADED:-}" ]] && return 0
_TOWER_ERROR_RECOVERY_LOADED=1

# Note: This file should be sourced AFTER common.sh
# It requires: _log_to_file, get_nav_caller, nav_tmux (from common.sh)

# ============================================================================
# Configuration
# ============================================================================

readonly ERROR_MAX_CONSECUTIVE="${ERROR_MAX_CONSECUTIVE:-5}"

# ============================================================================
# Color Definitions (fallback if not defined by caller)
# ============================================================================

# Define colors with fallbacks - only if not already defined (avoid readonly conflicts)
[[ -z "${NAV_C_HEADER:-}" ]] && NAV_C_HEADER=$'\033[38;5;241m'
[[ -z "${NAV_C_NORMAL:-}" ]] && NAV_C_NORMAL=$'\033[0m'
[[ -z "${NAV_C_DIM:-}" ]] && NAV_C_DIM=$'\033[38;5;245m'
# C_RED and C_RESET are defined as readonly in common.sh, use them directly
readonly ERROR_COOLDOWN_SECONDS="${ERROR_COOLDOWN_SECONDS:-2}"
readonly ERROR_BOX_WIDTH=45

# ============================================================================
# Safe Command Execution
# ============================================================================

# Safe execution wrapper that never exits the script
# Temporarily disables errexit to capture failures
#
# Arguments:
#   $1 - Error message prefix (for logging)
#   $2... - Command to execute
# Returns:
#   Command exit code (0 = success, non-zero = failure)
# Side effects:
#   Logs failures to tower.log
try_command() {
    local error_prefix="$1"
    shift
    local exit_code=0

    # Save current errexit state
    local errexit_was_set=0
    [[ $- == *e* ]] && errexit_was_set=1

    # Temporarily disable errexit
    set +e
    "$@" 2>&1
    exit_code=$?

    # Restore errexit if it was set
    [[ $errexit_was_set -eq 1 ]] && set -e

    if [[ $exit_code -ne 0 ]]; then
        _log_to_file "ERROR" "$error_prefix: Command failed (exit $exit_code): $*"
    fi

    return $exit_code
}

# Execute command with retry logic for transient failures
#
# Arguments:
#   $1 - Max retries (e.g., 3)
#   $2 - Delay between retries in seconds (e.g., 1)
#   $3... - Command to execute
# Returns:
#   0 on success, last exit code on final failure
# Side effects:
#   Logs each retry attempt
try_with_retry() {
    local max_retries="$1"
    local delay="$2"
    shift 2

    local attempt=1
    local exit_code=0

    # Save errexit state
    local errexit_was_set=0
    [[ $- == *e* ]] && errexit_was_set=1

    while [[ $attempt -le $max_retries ]]; do
        set +e
        "$@" 2>&1
        exit_code=$?
        [[ $errexit_was_set -eq 1 ]] && set -e

        if [[ $exit_code -eq 0 ]]; then
            return 0
        fi

        _log_to_file "WARN" "Attempt $attempt/$max_retries failed (exit $exit_code): $*"

        if [[ $attempt -lt $max_retries ]]; then
            sleep "$delay"
        fi
        ((attempt++)) || true
    done

    _log_to_file "ERROR" "All $max_retries attempts failed: $*"
    return $exit_code
}

# ============================================================================
# TUI Error Display Components
# ============================================================================

# Display error in TUI box (does not exit)
# Creates a visually consistent error box within the Navigator TUI
#
# Arguments:
#   $1 - Error title (e.g., "Connection Error")
#   $2 - Error message (can be multi-line, will be word-wrapped)
#   $3 - Recovery hint (optional, default: "Press any key to retry, 'q' to quit")
# Returns:
#   Nothing (displays to stdout)
show_tui_error() {
    local title="${1:-Error}"
    local message="${2:-An unexpected error occurred}"
    local hint="${3:-Press any key to retry, 'q' to quit}"

    local box_width="$ERROR_BOX_WIDTH"
    local inner_width=$((box_width - 4))

    # Generate horizontal border
    local border_h=""
    for ((i=0; i<box_width-2; i++)); do
        border_h+="─"
    done

    # Hide cursor and clear screen
    printf '\033[?25l'
    clear

    echo ""

    # Top border
    echo "  ${NAV_C_HEADER}┌─${border_h}─┐${NAV_C_NORMAL}"

    # Title line (with red color)
    local title_display="${C_RED}${title}${C_RESET}"
    local title_plain_len=${#title}
    local title_padding=$((inner_width - title_plain_len))
    printf "  ${NAV_C_HEADER}│${NAV_C_NORMAL} %s%*s ${NAV_C_HEADER}│${NAV_C_NORMAL}\n" \
        "$title_display" "$title_padding" ""

    # Separator
    echo "  ${NAV_C_HEADER}├─${border_h}─┤${NAV_C_NORMAL}"

    # Empty line
    printf "  ${NAV_C_HEADER}│${NAV_C_NORMAL} %*s ${NAV_C_HEADER}│${NAV_C_NORMAL}\n" "$inner_width" ""

    # Message lines (word-wrapped)
    echo "$message" | fold -w "$inner_width" -s | while IFS= read -r line; do
        printf "  ${NAV_C_HEADER}│${NAV_C_NORMAL} %-*s ${NAV_C_HEADER}│${NAV_C_NORMAL}\n" \
            "$inner_width" "$line"
    done

    # Empty line
    printf "  ${NAV_C_HEADER}│${NAV_C_NORMAL} %*s ${NAV_C_HEADER}│${NAV_C_NORMAL}\n" "$inner_width" ""

    # Separator before hint
    echo "  ${NAV_C_HEADER}├─${border_h}─┤${NAV_C_NORMAL}"

    # Hint line (dimmed)
    printf "  ${NAV_C_HEADER}│${NAV_C_NORMAL} ${NAV_C_DIM}%-*s${NAV_C_NORMAL} ${NAV_C_HEADER}│${NAV_C_NORMAL}\n" \
        "$inner_width" "$hint"

    # Bottom border
    echo "  ${NAV_C_HEADER}└─${border_h}─┘${NAV_C_NORMAL}"

    echo ""

    # Show cursor again
    printf '\033[?25h'
}

# Display a transient status message (auto-clears)
# Useful for "Retrying..." type messages
#
# Arguments:
#   $1 - Status message
#   $2 - Duration in seconds (optional, default: 1)
show_tui_status() {
    local message="$1"
    local duration="${2:-1}"

    local box_width="$ERROR_BOX_WIDTH"
    local inner_width=$((box_width - 4))

    local border_h=""
    for ((i=0; i<box_width-2; i++)); do
        border_h+="─"
    done

    printf '\033[?25l'
    clear

    echo ""
    echo "  ${NAV_C_HEADER}┌─${border_h}─┐${NAV_C_NORMAL}"
    printf "  ${NAV_C_HEADER}│${NAV_C_NORMAL} %-*s ${NAV_C_HEADER}│${NAV_C_NORMAL}\n" "$inner_width" ""
    printf "  ${NAV_C_HEADER}│${NAV_C_NORMAL} %-*s ${NAV_C_HEADER}│${NAV_C_NORMAL}\n" "$inner_width" "$message"
    printf "  ${NAV_C_HEADER}│${NAV_C_NORMAL} %-*s ${NAV_C_HEADER}│${NAV_C_NORMAL}\n" "$inner_width" ""
    echo "  ${NAV_C_HEADER}└─${border_h}─┘${NAV_C_NORMAL}"
    echo ""

    printf '\033[?25h'

    sleep "$duration"
}

# Wait for user input after error
# Returns user's choice for recovery action
#
# Returns:
#   "retry" - User wants to retry (any key except q/Q)
#   "quit" - User wants to quit Navigator (q/Q)
wait_error_response() {
    local key=""
    read -rsn1 key

    case "$key" in
        q|Q) echo "quit" ;;
        *)   echo "retry" ;;
    esac
}

# ============================================================================
# Recovery Actions
# ============================================================================

# Return to caller session gracefully
# Used when user quits Navigator or on fatal error
#
# This function:
#   1. Gets the saved caller session
#   2. Validates it still exists
#   3. Uses detach-client -E to seamlessly return
#   4. Falls back to any available session if caller gone
return_to_caller() {
    local caller
    caller=$(get_nav_caller 2>/dev/null || echo "")

    _log_to_file "INFO" "Returning to caller session: ${caller:-<none>}"

    # Determine target - check session server first, then default server
    local target_session=""
    local target_socket=""

    if [[ -n "$caller" ]]; then
        if session_tmux has-session -t "$caller" 2>/dev/null; then
            target_session="$caller"
            target_socket="$TOWER_SESSION_SOCKET"
        elif TMUX= tmux has-session -t "$caller" 2>/dev/null; then
            target_session="$caller"
            target_socket=""
        fi
    fi

    # Fallback: find any session on session server first, then default server
    if [[ -z "$target_session" ]]; then
        target_session=$(session_tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")
        [[ -n "$target_session" ]] && target_socket="$TOWER_SESSION_SOCKET"
    fi
    if [[ -z "$target_session" ]]; then
        target_session=$(TMUX= tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")
        target_socket=""
    fi

    if [[ -n "$target_session" ]]; then
        _log_to_file "INFO" "Attaching to: $target_session (socket: ${target_socket:-default})"
        if [[ -n "$target_socket" ]]; then
            nav_tmux detach-client -E "TMUX= tmux -L '$target_socket' attach-session -t '$target_session'" 2>/dev/null || true
        else
            nav_tmux detach-client -E "TMUX= tmux attach-session -t '$target_session'" 2>/dev/null || true
        fi
    else
        _log_to_file "WARN" "No sessions available, just detaching"
        nav_tmux detach-client 2>/dev/null || true
    fi
}

# ============================================================================
# Main Loop Recovery Wrapper
# ============================================================================

# Error-safe main loop wrapper
# Wraps the entire main loop in error handling to prevent crashes
#
# Arguments:
#   $1 - Script name (for logging)
#   $2 - Main loop function name (will be called repeatedly)
# Returns:
#   0 on graceful exit, 1 on fatal error
#
# Behavior:
#   - Catches all errors from main loop
#   - Displays TUI error on failure
#   - Auto-restarts with cooldown
#   - Allows user to quit cleanly
#   - Prevents infinite crash loops (max consecutive errors)
run_with_recovery() {
    local script_name="$1"
    local main_func="$2"
    local consecutive_errors=0

    _log_to_file "INFO" "$script_name: Starting with recovery wrapper"

    while true; do
        # Save errexit state
        local errexit_was_set=0
        [[ $- == *e* ]] && errexit_was_set=1

        # Disable errexit for the main loop
        set +e

        # Run main function - note: we call it directly, not capturing output
        # This allows interactive features to work
        "$main_func"
        local exit_code=$?

        # Restore errexit if it was set
        [[ $errexit_was_set -eq 1 ]] && set -e

        # Check if this was a clean exit (exit code 0)
        if [[ $exit_code -eq 0 ]]; then
            _log_to_file "INFO" "$script_name: Clean exit from main loop"
            return 0
        fi

        # Error occurred
        ((consecutive_errors++)) || true

        _log_to_file "ERROR" "$script_name: Main loop failed (exit $exit_code, consecutive: $consecutive_errors)"

        # Check for too many consecutive errors
        if [[ $consecutive_errors -ge $ERROR_MAX_CONSECUTIVE ]]; then
            show_tui_error \
                "Critical Error" \
                "Navigator crashed $consecutive_errors times consecutively. This may indicate a serious problem. Check logs: $TOWER_LOG_FILE" \
                "Press 'q' to quit, any key to force restart"

            local response
            response=$(wait_error_response)

            if [[ "$response" == "quit" ]]; then
                _log_to_file "INFO" "$script_name: User chose to quit after critical errors"
                return_to_caller
                return 1
            fi

            # User wants to force restart - reset counter
            consecutive_errors=0
            _log_to_file "INFO" "$script_name: User forced restart after critical errors"
        else
            show_tui_error \
                "Recovering..." \
                "Navigator encountered an error. Automatically restarting in ${ERROR_COOLDOWN_SECONDS}s..." \
                "Press 'q' to quit Navigator"

            # Wait with timeout for user input
            local key=""
            if read -rsn1 -t "$ERROR_COOLDOWN_SECONDS" key; then
                if [[ "$key" == "q" || "$key" == "Q" ]]; then
                    _log_to_file "INFO" "$script_name: User chose to quit during recovery"
                    return_to_caller
                    return 1
                fi
            fi
        fi

        _log_to_file "INFO" "$script_name: Restarting main loop (attempt after error)"
    done
}

# ============================================================================
# Safe tmux Wrappers for Navigator
# ============================================================================

# Safe nav_tmux wrapper that handles failures gracefully
# Never causes script exit, always returns exit code
#
# Arguments:
#   $@ - tmux command and arguments (passed to nav_tmux)
# Returns:
#   tmux exit code (0 = success)
# Side effects:
#   Logs failures to tower.log
safe_nav_tmux() {
    local cmd="$1"
    shift

    local errexit_was_set=0
    [[ $- == *e* ]] && errexit_was_set=1

    set +e
    local output
    output=$(nav_tmux "$cmd" "$@" 2>&1)
    local exit_code=$?
    [[ $errexit_was_set -eq 1 ]] && set -e

    if [[ $exit_code -ne 0 ]]; then
        _log_to_file "WARN" "safe_nav_tmux $cmd failed (exit $exit_code): $output"
    fi

    # Only output if there was output
    [[ -n "$output" ]] && echo "$output"
    return $exit_code
}

# Safe signal to view pane (never fails script)
# Sends Escape key to trigger view refresh
safe_signal_view() {
    nav_tmux send-keys -t "$TOWER_NAV_SESSION:0.1" Escape 2>/dev/null || true
}

# ============================================================================
# Pane Monitoring Hooks Setup
# ============================================================================

# Setup auto-restart hooks for Navigator panes
# Called after panes are created in navigator.sh
#
# This creates tmux hooks that automatically respawn crashed panes
# so the user never sees a shell prompt in Navigator
setup_pane_auto_restart() {
    local script_dir="${1:-$SCRIPT_DIR}"

    _log_to_file "INFO" "Setting up pane auto-restart hooks"

    # Hook for when any pane in Navigator exits
    # Uses respawn-pane to restart the appropriate script
    nav_tmux set-hook -t "$TOWER_NAV_SESSION" pane-exited \
        "run-shell 'sleep 0.5 && \
            if [ #{pane_index} -eq 0 ]; then \
                tmux -L $TOWER_NAV_SOCKET respawn-pane -t $TOWER_NAV_SESSION:0.0 \"$script_dir/navigator-list.sh\"; \
            elif [ #{pane_index} -eq 1 ]; then \
                tmux -L $TOWER_NAV_SOCKET respawn-pane -t $TOWER_NAV_SESSION:0.1 \"$script_dir/navigator-view.sh\"; \
            fi'" 2>/dev/null || true
}

# ============================================================================
# Error Classification Helpers
# ============================================================================

# Classify error type for appropriate handling
# Arguments:
#   $1 - Exit code
#   $2 - Error message/output
# Returns:
#   Error type: "transient", "session_missing", "config", "fatal"
classify_error() {
    local exit_code="$1"
    local error_msg="$2"

    case "$error_msg" in
        *"session not found"*|*"no session"*)
            echo "session_missing"
            ;;
        *"server not found"*|*"no server"*|*"connection refused"*)
            echo "transient"
            ;;
        *"config"*|*"not found"*|*"missing"*)
            echo "config"
            ;;
        *)
            if [[ $exit_code -eq 1 ]]; then
                echo "transient"
            else
                echo "fatal"
            fi
            ;;
    esac
}

# Get recommended action for error type
# Arguments:
#   $1 - Error type from classify_error
# Returns:
#   Action: "retry", "refresh", "warn", "exit"
get_error_action() {
    local error_type="$1"

    case "$error_type" in
        transient)      echo "retry" ;;
        session_missing) echo "refresh" ;;
        config)         echo "warn" ;;
        fatal)          echo "exit" ;;
        *)              echo "retry" ;;
    esac
}
