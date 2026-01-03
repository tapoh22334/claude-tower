# Navigator TUI Error Handling and Recovery Strategy

## Architecture Design Document

**Author:** Hive Mind Architect Agent
**Date:** 2026-01-02
**Version:** 1.0

---

## 1. Problem Analysis

### 1.1 Current Issues

1. **`set -euo pipefail` causes immediate script termination**
   - Any command failure triggers ERR trap and exits
   - Script returns to terminal without user feedback
   - No recovery opportunity

2. **Navigator pane crashes are unrecoverable**
   - When `navigator-list.sh` or `navigator-view.sh` crash, the pane shows shell prompt
   - User must manually restart Navigator
   - No auto-restart mechanism

3. **Error messages are not user-visible**
   - Errors go to log file only
   - TUI box disappears on crash
   - User sees raw terminal instead of friendly error

4. **No graceful degradation**
   - Single command failure brings down entire script
   - No retry logic for transient failures
   - No fallback behaviors

### 1.2 Root Cause Analysis

```
Current Flow (Problematic):
  Script Start
       |
  set -euo pipefail  <-- Enables strict mode
       |
  Command Fails  <-- e.g., tmux command returns non-zero
       |
  ERR Trap Fires  <-- Logs error to file
       |
  Script Exits  <-- Returns to terminal (bad!)
       |
  Pane Shows Shell  <-- User confused
```

---

## 2. Design Goals

1. **Never crash to terminal** - Always show error in TUI
2. **Auto-restart crashed panes** - Self-healing behavior
3. **User-friendly error display** - Clear messages in TUI box
4. **Detailed logging** - Debug info in log file
5. **Recovery options** - Retry/escape for user
6. **Graceful degradation** - Partial functionality when possible

---

## 3. Proposed Architecture

### 3.1 Error Handling Layers

```
Layer 4: User Interface (TUI Error Display)
         |
Layer 3: Recovery Actions (Auto-restart, Retry)
         |
Layer 2: Error Classification (Transient, Fatal, User)
         |
Layer 1: Error Capture (Wrapper Functions)
         |
Layer 0: Safe Command Execution (try_* functions)
```

### 3.2 Component Diagram

```
+------------------------------------------------------------------+
|                        Navigator Session                          |
|  +----------------------------+  +----------------------------+   |
|  |     Left Pane (List)       |  |    Right Pane (View)       |   |
|  |  +----------------------+  |  |  +----------------------+  |   |
|  |  | navigator-list.sh   |  |  |  | navigator-view.sh   |  |   |
|  |  +----------------------+  |  |  +----------------------+  |   |
|  |           |                |  |           |                |   |
|  |  +----------------------+  |  |  +----------------------+  |   |
|  |  | Error Wrapper Loop   |  |  |  | Error Wrapper Loop   |  |   |
|  |  | - Catches all errors |  |  |  | - Catches all errors |  |   |
|  |  | - Shows TUI error    |  |  |  | - Shows TUI error    |  |   |
|  |  | - Auto-restarts      |  |  |  | - Auto-restarts      |  |   |
|  |  +----------------------+  |  |  +----------------------+  |   |
|  +----------------------------+  +----------------------------+   |
|                                                                    |
|  +--------------------------------------------------------------+  |
|  |                   Pane Monitor (tmux hooks)                  |  |
|  |  - Detects pane exit                                         |  |
|  |  - Triggers auto-restart                                     |  |
|  |  - Logs crash events                                         |  |
|  +--------------------------------------------------------------+  |
+------------------------------------------------------------------+
```

---

## 4. Detailed Design

### 4.1 Error Wrapper Function

Location: `lib/error-recovery.sh`

```bash
# Safe execution wrapper that never exits the script
# Arguments:
#   $1 - Error message prefix
#   $2... - Command to execute
# Returns:
#   Command exit code (captured, not causing script exit)
try_command() {
    local error_prefix="$1"
    shift
    local exit_code=0

    # Temporarily disable errexit
    set +e
    "$@" 2>&1
    exit_code=$?
    set -e

    if [[ $exit_code -ne 0 ]]; then
        _log_to_file "ERROR" "$error_prefix: Command failed (exit $exit_code): $*"
    fi

    return $exit_code
}

# Execute command with retry logic
# Arguments:
#   $1 - Max retries
#   $2 - Delay between retries (seconds)
#   $3... - Command to execute
# Returns:
#   0 on success, last exit code on final failure
try_with_retry() {
    local max_retries="$1"
    local delay="$2"
    shift 2

    local attempt=1
    local exit_code=0

    while [[ $attempt -le $max_retries ]]; do
        set +e
        "$@" 2>&1
        exit_code=$?
        set -e

        if [[ $exit_code -eq 0 ]]; then
            return 0
        fi

        _log_to_file "WARN" "Attempt $attempt/$max_retries failed (exit $exit_code): $*"

        if [[ $attempt -lt $max_retries ]]; then
            sleep "$delay"
        fi
        ((attempt++))
    done

    _log_to_file "ERROR" "All $max_retries attempts failed: $*"
    return $exit_code
}
```

### 4.2 TUI Error Display Component

```bash
# Display error in TUI box (does not exit)
# Arguments:
#   $1 - Error title
#   $2 - Error message
#   $3 - Recovery hint (optional)
show_tui_error() {
    local title="${1:-Error}"
    local message="${2:-An unexpected error occurred}"
    local hint="${3:-Press any key to retry, 'q' to quit}"

    local box_width=45
    local border_h="$(printf '─%.0s' $(seq 1 $((box_width-2))))"

    clear
    echo ""
    echo "  ${NAV_C_HEADER}┌─${border_h}─┐${NAV_C_NORMAL}"
    echo "  ${NAV_C_HEADER}│${NAV_C_NORMAL} ${C_RED}${title}${C_RESET}$(printf '%*s' $((box_width-${#title}-3)) '')${NAV_C_HEADER}│${NAV_C_NORMAL}"
    echo "  ${NAV_C_HEADER}├─${border_h}─┤${NAV_C_NORMAL}"

    # Word-wrap message to fit box
    echo "$message" | fold -w $((box_width-4)) | while IFS= read -r line; do
        printf "  ${NAV_C_HEADER}│${NAV_C_NORMAL} %-$((box_width-4))s ${NAV_C_HEADER}│${NAV_C_NORMAL}\n" "$line"
    done

    echo "  ${NAV_C_HEADER}├─${border_h}─┤${NAV_C_NORMAL}"
    printf "  ${NAV_C_HEADER}│${NAV_C_NORMAL} ${NAV_C_DIM}%-$((box_width-4))s${NAV_C_NORMAL} ${NAV_C_HEADER}│${NAV_C_NORMAL}\n" "$hint"
    echo "  ${NAV_C_HEADER}└─${border_h}─┘${NAV_C_NORMAL}"
    echo ""
}

# Wait for user input after error
# Returns:
#   "retry" - User wants to retry
#   "quit" - User wants to quit
wait_error_response() {
    local key=""
    read -rsn1 key

    case "$key" in
        q|Q) echo "quit" ;;
        *)   echo "retry" ;;
    esac
}
```

### 4.3 Main Loop Error Wrapper

```bash
# Error-safe main loop wrapper
# This wraps the entire main loop in error handling
# Arguments:
#   $1 - Script name (for logging)
#   $2 - Main loop function name
run_with_recovery() {
    local script_name="$1"
    local main_func="$2"
    local consecutive_errors=0
    local max_consecutive_errors=5
    local error_cooldown=2

    while true; do
        # Disable errexit for the main loop
        set +e

        # Run main function and capture any errors
        local error_output=""
        error_output=$("$main_func" 2>&1)
        local exit_code=$?

        set -e

        if [[ $exit_code -ne 0 ]]; then
            ((consecutive_errors++))

            _log_to_file "ERROR" "$script_name crashed (consecutive: $consecutive_errors): $error_output"

            if [[ $consecutive_errors -ge $max_consecutive_errors ]]; then
                show_tui_error \
                    "Critical Error" \
                    "Navigator crashed $consecutive_errors times. Please check logs at: $TOWER_LOG_FILE" \
                    "Press 'q' to quit, any other key to force restart"

                local response
                response=$(wait_error_response)

                if [[ "$response" == "quit" ]]; then
                    # Return to caller session gracefully
                    return_to_caller
                    return 1
                fi

                consecutive_errors=0
            else
                show_tui_error \
                    "Recovering..." \
                    "Navigator encountered an error. Restarting in ${error_cooldown}s..." \
                    "Press 'q' to quit Navigator"

                # Wait with timeout for user input
                local key=""
                if read -rsn1 -t "$error_cooldown" key; then
                    if [[ "$key" == "q" || "$key" == "Q" ]]; then
                        return_to_caller
                        return 1
                    fi
                fi
            fi

            # Cooldown before restart
            sleep "$error_cooldown"
        else
            # Successful iteration resets error count
            consecutive_errors=0
        fi
    done
}

# Return to caller session gracefully
return_to_caller() {
    local caller
    caller=$(get_nav_caller)

    if [[ -n "$caller" ]] && TMUX= tmux has-session -t "$caller" 2>/dev/null; then
        nav_tmux detach-client -E "TMUX= tmux attach-session -t '$caller'"
    else
        local fallback
        fallback=$(TMUX= tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")
        if [[ -n "$fallback" ]]; then
            nav_tmux detach-client -E "TMUX= tmux attach-session -t '$fallback'"
        else
            nav_tmux detach-client
        fi
    fi
}
```

### 4.4 Auto-Restart Mechanism via tmux Hooks

Add to `navigator.sh` after creating panes:

```bash
# Setup auto-restart hooks for panes
setup_pane_monitoring() {
    local list_pane="$TOWER_NAV_SESSION:0.0"
    local view_pane="$TOWER_NAV_SESSION:0.1"

    # Monitor left pane (list)
    nav_tmux set-hook -t "$TOWER_NAV_SESSION" pane-exited \
        "if-shell '[ #{pane_index} -eq 0 ]' \
            'respawn-pane -t $list_pane \"$SCRIPT_DIR/navigator-list.sh\"'"

    # Monitor right pane (view)
    nav_tmux set-hook -t "$TOWER_NAV_SESSION" pane-exited \
        "if-shell '[ #{pane_index} -eq 1 ]' \
            'respawn-pane -t $view_pane \"$SCRIPT_DIR/navigator-view.sh\"'"
}
```

### 4.5 Safe tmux Command Wrappers

```bash
# Safe nav_tmux wrapper that handles failures gracefully
safe_nav_tmux() {
    local cmd="$1"
    shift

    set +e
    local output
    output=$(nav_tmux "$cmd" "$@" 2>&1)
    local exit_code=$?
    set -e

    if [[ $exit_code -ne 0 ]]; then
        _log_to_file "WARN" "nav_tmux $cmd failed (exit $exit_code): $output"
    fi

    echo "$output"
    return $exit_code
}

# Safe signal to view pane (never fails)
safe_signal_view() {
    nav_tmux send-keys -t "$TOWER_NAV_SESSION:0.1" Escape 2>/dev/null || true
}
```

---

## 5. Recovery Flow Diagram

```
                    Script Starts
                         |
                         v
              +-------------------+
              | Initialize Error  |
              | Handling Context  |
              +-------------------+
                         |
                         v
              +-------------------+
              | run_with_recovery |<--------+
              |   (main wrapper)  |         |
              +-------------------+         |
                         |                  |
                         v                  |
              +-------------------+         |
              | Execute Main Loop |         |
              +-------------------+         |
                    |         |             |
                    v         v             |
              +--------+  +--------+        |
              |Success |  | Error  |        |
              +--------+  +--------+        |
                    |         |             |
                    v         v             |
              +--------+  +---------------+ |
              |Continue|  |Show TUI Error | |
              +--------+  +---------------+ |
                    |         |             |
                    |         v             |
                    |   +---------------+   |
                    |   |User Response? |   |
                    |   +---------------+   |
                    |     |         |       |
                    |     v         v       |
                    | +-retry-+ +-quit-+    |
                    | |       | |      |    |
                    | v       | v      |    |
                    +---------+ Return |    |
                              | to     |    |
                              | Caller |----+
                              +--------+
```

---

## 6. Implementation Plan

### Phase 1: Core Error Infrastructure (lib/error-recovery.sh)

1. Create `try_command()` wrapper
2. Create `try_with_retry()` for transient failures
3. Create `show_tui_error()` display function
4. Create `run_with_recovery()` main loop wrapper

### Phase 2: Update navigator-list.sh

1. Remove `set -e` (keep `-uo pipefail`)
2. Wrap main_loop in `run_with_recovery`
3. Add `try_command` to all tmux operations
4. Add error display in TUI box

### Phase 3: Update navigator-view.sh

1. Same changes as list.sh
2. Add graceful fallback when session attachment fails

### Phase 4: Add Auto-Restart Hooks

1. Add pane-exited hooks in navigator.sh
2. Use respawn-pane for automatic restart
3. Log restart events

### Phase 5: Integration Testing

1. Test intentional crashes
2. Verify auto-restart works
3. Confirm error messages display correctly
4. Test recovery to caller session

---

## 7. Error Classification

| Type | Example | Recovery |
|------|---------|----------|
| Transient | tmux server busy | Auto-retry with backoff |
| Session Missing | Target session deleted | Show message, refresh list |
| Config Error | Missing view-focus.conf | Show error, continue without |
| Fatal | No tmux available | Show error, exit gracefully |
| User Cancel | Press 'q' in error dialog | Return to caller |

---

## 8. Logging Strategy

```bash
# Error levels and destinations
DEBUG  -> Log file only (when TOWER_DEBUG=1)
INFO   -> Log file only
WARN   -> Log file only
ERROR  -> Log file + TUI display
FATAL  -> Log file + TUI display + Exit gracefully
```

Log format:
```
[2026-01-02 10:30:45] [ERROR] [navigator-list.sh] Session not found: tower_example
```

---

## 9. Testing Checklist

- [ ] Script survives `tmux kill-session` of target
- [ ] Script survives `tmux kill-server` of default server
- [ ] Error box displays correctly
- [ ] Auto-restart works after crash
- [ ] 'q' in error dialog returns to caller
- [ ] Log file captures all errors
- [ ] No shell prompt ever visible in panes
- [ ] Recovery from 5+ consecutive errors
- [ ] Graceful handling of missing config files

---

## 10. Security Considerations

1. **Log file permissions**: Ensure 600 permissions on log file
2. **No secrets in logs**: Never log session content or commands
3. **Path validation**: Continue using `validate_path_within`
4. **Input sanitization**: All user input through `sanitize_name`

---

## Appendix A: Example Error Scenarios

### A.1 Session Deleted While Viewing

```
User Action: Delete session from another terminal
Current Behavior: View pane shows error, might crash
New Behavior:
  1. View pane detects session missing
  2. Shows TUI error: "Session no longer exists"
  3. Waits for keypress
  4. Returns to placeholder view
  5. List pane refreshes automatically
```

### A.2 tmux Server Restart

```
Event: Default tmux server restarted
Current Behavior: Both panes crash
New Behavior:
  1. Panes detect connection failure
  2. Show TUI error: "Connection lost - tmux server restarted"
  3. Auto-retry connection every 2 seconds
  4. Resume normal operation when server available
```

### A.3 Invalid Session Selection

```
Event: Session ID in state file is corrupted
Current Behavior: Undefined behavior, possible crash
New Behavior:
  1. validate_tower_session_id fails
  2. Clear invalid selection
  3. Show TUI warning: "Invalid session cleared"
  4. Default to first available session
```
