#!/usr/bin/env bash
# shellcheck shell=bash
# nav-actions.sh - What a key actually does: add, fork, delete, restore, switch, quit.
#
# Owns the handlers that change the world (sessions, panes, modes), as
# opposed to the loop that reads the key or the code that draws the result.

# ============================================================================
# Actions
# ============================================================================

# Focus on view pane (enables input to selected session)
# Simply moves tmux pane focus - no mode switching needed since view always attaches in input mode
focus_view() {
    set_nav_focus "view"
    nav_tmux select-pane -t "$TOWER_NAV_SESSION:0.1"
}

# Where an interactive sub-flow's stderr goes. The list pane's own stderr is
# a log file (nav_pane_command), and session-add.sh talks to the person on
# stderr: prompts, the numbered picker, "Create? [y/N]", handle_error text,
# git worktree output. Without this they land in the log and the pane stays
# blank while it waits for input (#23 by another route). Tests, which have
# no controlling terminal, keep stderr where bats can capture it. Callers
# use `2>>`: on Linux `>/dev/stderr` reopens fd 2's file with O_TRUNC, which
# would wipe the log this is meant to spare.
_subflow_tty() {
    if { : </dev/tty; } 2>/dev/null; then
        echo /dev/tty
    else
        echo /dev/stderr
    fi
}

# Unified add/new flow (session-add.sh). Runs interactively in this pane;
# fzf draws on the tty, the chosen tower_<id> comes back on stdout.
add_session_inline() {
    clear
    local new_id
    new_id=$(TOWER_ADD_DEFAULT_DIR="$(get_caller_cwd)" "$SCRIPT_DIR/session-add.sh" --print-id 2>>"$(_subflow_tty)") || {
        return 0  # cancelled or failed; messages already shown
    }
    if [[ -n "$new_id" ]]; then
        set_nav_selected "$new_id"
        signal_view_update
        # Seat the row now: without it the list has no entry for the session
        # the user just made, so it stays invisible until the next rebuild and
        # the selection lookup cannot find it.
        # No dir here: the caller cwd was only the picker's default and the
        # user may have chosen elsewhere; the seat resolves the real one.
        _remember_session_row "$new_id" "" || true
    fi
}

# Fork here: start a brand-new session in the selected session's project
# dir, no prompts. The new session is registered and selected.
fork_session_here() {
    local selected dir new_id
    selected=$(get_nav_selected)
    if [[ -z "$selected" ]]; then
        return 0
    fi
    dir=$(_session_dir "$selected")
    if [[ -z "$dir" || ! -d "$dir" ]]; then
        echo ""
        echo "  ${NAV_C_DIM}No directory known for this session${NAV_C_NORMAL}"
        sleep 0.5
        return 0
    fi
    clear
    new_id=$("$SCRIPT_DIR/session-add.sh" --fork-dir "$dir" --print-id 2>>"$(_subflow_tty)") || return 0
    if [[ -n "$new_id" ]]; then
        set_nav_selected "$new_id"
        signal_view_update
        _remember_session_row "$new_id" "$dir" || true
    fi
}

# Pick a known project directory and start a new session there.
new_session_pick_dir() {
    clear
    local new_id
    new_id=$("$SCRIPT_DIR/session-add.sh" --new-in-dir --print-id 2>>"$(_subflow_tty)") || return 0
    if [[ -n "$new_id" ]]; then
        set_nav_selected "$new_id"
        signal_view_update
        # The picker chose the directory and session-add.sh saved it as
        # launch_dir; _remember_session_row reads it back to seat the row.
        _remember_session_row "$new_id" "" || true
    fi
}

# Working directory of the caller pane (default dir for new sessions)
get_caller_cwd() {
    local caller cwd=""
    caller=$(get_nav_caller)
    if [[ -n "$caller" ]]; then
        cwd=$(session_tmux display-message -t "$caller" -p '#{pane_current_path}' 2>/dev/null) ||
            cwd=$(TMUX= tmux display-message -t "$caller" -p '#{pane_current_path}' 2>/dev/null) ||
            cwd=""
    fi
    echo "${cwd:-$HOME}"
}

# Ask whether to delete the selected session. Prompt only — no deletion
# happens here, so the caller can mark the row as deleting and repaint before
# committing to it. 0 = go ahead, 1 = cancelled (declined or timed out).
confirm_delete_selected() {
    local selected="$1"
    local name="${selected#tower_}"
    local term_height
    term_height=$(_term_lines)

    # Move cursor to bottom of list area and show confirmation UI
    tput cup "$((term_height - 5))" 0 2>/dev/null || true
    echo -e "${NAV_C_HEADER}┌─ Delete Session ────────┐${NAV_C_NORMAL}"
    echo -e "│ Session: ${NAV_C_ACCENT}${name}${NAV_C_NORMAL}"
    printf "│ Confirm? [y/n]: "

    local confirm=""
    if ! read -rsn1 -t 10 confirm; then
        echo ""
        echo -e "│ ${NAV_C_DIM}Cancelled (timeout)${NAV_C_NORMAL}"
        echo -e "${NAV_C_HEADER}└─────────────────────────┘${NAV_C_NORMAL}"
        sleep 0.5
        return 1
    fi
    echo ""

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        # Close the box here too: the caller repaints the list next, and
        # leaving the frame open would strand a dangling edge on screen for
        # anyone whose terminal draws it before the repaint lands.
        echo -e "${NAV_C_HEADER}└─────────────────────────┘${NAV_C_NORMAL}"
        return 0
    fi
    echo -e "│ ${NAV_C_DIM}Cancelled${NAV_C_NORMAL}"
    echo -e "${NAV_C_HEADER}└─────────────────────────┘${NAV_C_NORMAL}"
    return 1
}

# Run the delete for an already-confirmed session, reporting the outcome in a
# box of its own.
#
# It draws its own box rather than closing the confirmation one, because the
# caller repaints the list in between (to show the row as deleting) and that
# repaint runs over whatever the confirmation left on screen. Positioning from
# scratch here is what keeps the result legible either way.
execute_delete() {
    local selected="$1"
    local term_height
    term_height=$(_term_lines)
    tput cup "$((term_height - 3))" 0 2>/dev/null || true
    if TOWER_QUIET_ERRORS=1 "$SCRIPT_DIR/session-delete.sh" "$selected" --force 2>/dev/null; then
        echo -e "${NAV_C_HEADER}┌─────────────────────────┐${NAV_C_NORMAL}"
        echo -e "│ ${NAV_C_ACCENT}✓${NAV_C_NORMAL} Deleted"
        echo -e "${NAV_C_HEADER}└─────────────────────────┘${NAV_C_NORMAL}"
        # No pause on the success path — the row vanishing from the list is
        # the confirmation. Waiting only delays the next keystroke.
        return 0
    fi
    # Hold this one: a failure the user misses leaves them thinking the
    # session went away when it did not.
    echo -e "${NAV_C_HEADER}┌─────────────────────────┐${NAV_C_NORMAL}"
    echo -e "│ ${NAV_C_ERROR}✗${NAV_C_NORMAL} Delete failed"
    echo -e "${NAV_C_HEADER}└─────────────────────────┘${NAV_C_NORMAL}"
    sleep 0.8
    return 1
}

# Confirm and delete in one step, for callers with no list to mark up.
delete_selected() {
    local selected
    selected=$(get_nav_selected)
    [[ -n "$selected" ]] || return 1
    confirm_delete_selected "$selected" || return 1
    execute_delete "$selected"
}

# Restore selected session (idempotent)
# - dormant → restore
# - active → do nothing (already active)
# - no metadata → do nothing (can't restore)
restore_selected() {
    local selected
    selected=$(get_nav_selected)

    if [[ -z "$selected" ]]; then
        return 0
    fi

    # Check if session already exists (active) on session server
    if session_tmux has-session -t "$selected" 2>/dev/null; then
        # Already active - idempotent success
        echo ""
        echo "  ${NAV_C_DIM}Already active${NAV_C_NORMAL}"
        sleep 0.3
        return 0
    fi

    # Check if metadata exists (can restore)
    if ! has_metadata "$selected"; then
        # No metadata - can't restore
        echo ""
        echo "  ${NAV_C_DIM}Not registered — press n to add${NAV_C_NORMAL}"
        sleep 0.3
        return 0
    fi

    # Already running outside Tower's tmux: resuming would open a second
    # copy of a live session.
    if [[ "$(get_display_state "$selected")" == "external" ]]; then
        echo ""
        echo "  ${NAV_C_DIM}Running outside Tower (◇) — use its own terminal${NAV_C_NORMAL}"
        sleep 0.5
        return 0
    fi

    # Dormant - restore it
    echo ""
    echo "  ${NAV_C_ACCENT}Restoring...${NAV_C_NORMAL}"

    if "$SCRIPT_DIR/session-restore.sh" "$selected" 2>/dev/null; then
        echo "  ${NAV_C_ACCENT}✓${NAV_C_NORMAL} Restored: ${selected#tower_}"
        signal_view_update
        # Show it as starting straight away rather than leaving the row at ○
        # until the rebuild lands: every other action answers immediately, and
        # a restore that looks inert is the one most likely to be pressed
        # twice. No pause — the mark is the confirmation.
        _mark_session_starting "$selected" || true
        return 0
    fi
    echo "  ${NAV_C_ERROR}✗${NAV_C_NORMAL} Failed to restore"
    sleep 0.8
    return 1
}

# Switch to Tile mode
# Hand the terminal over to one of the full-screen views (tile/tail/queue).
#
# The view runs as a window on the session server, and we detach the
# Navigator so the user lands on it. Both halves must name the SAME session:
# `new-window` with no target goes to whatever session the server currently
# considers current, while the attach used to pick `list-sessions | head -1`.
# Those are different sessions as soon as more than one exists, so the user
# was detached onto a session that had no view window in it — the view had
# been created, just not where they were sent. That is the "tile mode does
# nothing" report.
_switch_to_view() {
    local window="$1" script="$2"
    local target
    target=$(session_tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")
    if [[ -z "$target" ]]; then
        handle_info "No sessions to show"
        return 0
    fi
    # -t pins the window to the session we are about to attach to. -e hands
    # the view this Navigator's effective settings: a new-window process gets
    # the SERVER's environment, not ours, so a Navigator running with
    # overridden sockets or state dir (tests, a second Tower) would otherwise
    # launch a view that reads and writes the default, live ones.
    if ! session_tmux new-window -t "$target" -n "$window" \
        -e "CLAUDE_TOWER_NAV_SOCKET=$TOWER_NAV_SOCKET" \
        -e "CLAUDE_TOWER_SESSION_SOCKET=$TOWER_SESSION_SOCKET" \
        -e "CLAUDE_TOWER_NAV_STATE_DIR=$TOWER_NAV_STATE_DIR" \
        -e "CLAUDE_TOWER_METADATA_DIR=$TOWER_METADATA_DIR" \
        -e "CLAUDE_PROJECTS_DIR=$CLAUDE_PROJECTS_DIR" \
        "$script" 2>/dev/null; then
        handle_error "Could not open $window"
        return 1
    fi
    nav_tmux detach-client -E "TMUX= tmux -L '$TOWER_SESSION_SOCKET' attach-session -t '$target'"
}

switch_to_tile() {
    info_log "Switching to Tile mode"
    _switch_to_view "tower-tile" "$SCRIPT_DIR/tile.sh"
}

# Switch to Tail view (live multi-session output follow)
switch_to_tail() {
    info_log "Switching to Tail mode"
    _switch_to_view "tower-tail" "$SCRIPT_DIR/tail-view.sh"
}

# Queue mode (sessions awaiting your action, oldest wait first).
#
# Unlike Tile and Tail, the queue is a way of looking at the same list, so it
# runs in THIS pane as a foreground sub-flow — the same shape as the help
# screen or the add prompt — and the view pane keeps following the shared
# selection while the user moves through it. Nothing is created on the
# session server and no client is attached from inside a pane, which is what
# made the old window-based queue nest the Navigator inside itself (#37).
#
# Returns 0 when the user came back to the list (the selection file already
# names the row they chose) and QUEUE_EXIT_QUIT when they pressed q there.
readonly QUEUE_EXIT_QUIT=3
switch_to_queue() {
    info_log "Switching to Queue mode"
    local rc=0
    "$SCRIPT_DIR/queue-view.sh" || rc=$?
    return "$rc"
}

# Quit Navigator
# Returns to the caller session or any available session on default server
quit_navigator() {
    local caller
    caller=$(get_nav_caller)

    info_log "Quitting Navigator, returning to caller: ${caller:-<none>}"

    # Determine target session - check session server first, then fall back to default server
    local target_session=""
    local target_socket=""

    if [[ -n "$caller" ]]; then
        if session_tmux has-session -t "$caller" 2>/dev/null; then
            target_session="$caller"
            target_socket="$TOWER_SESSION_SOCKET"
        elif TMUX= tmux has-session -t "$caller" 2>/dev/null; then
            target_session="$caller"
            target_socket=""  # default server
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
        # Use detach-client -E to seamlessly return to appropriate server
        if [[ -n "$target_socket" ]]; then
            nav_tmux detach-client -E "TMUX= tmux -L '$target_socket' attach-session -t '$target_session'"
        else
            nav_tmux detach-client -E "TMUX= tmux attach-session -t '$target_session'"
        fi
    else
        # No sessions available, just exit
        nav_tmux detach-client
    fi
}
