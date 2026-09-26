#!/usr/bin/env bash
# shellcheck shell=bash
# nav-loop.sh - The key loop: cursor movement, terminal state, main_loop.
#
# Owns selection movement, the echo/sub-flow terminal discipline, and the
# tick loop that binds keys to the handlers in the other nav files.

# Move selection and update view. Echoes the new index (callers capture it
# via $(...)); the view-pane signal fires asynchronously so this returns as
# soon as the local state file is updated — the command substitution no
# longer waits on the slow tmux round-trip because signal_view_update_async
# detaches the background job's fds.
# The movers publish the new index in NAV_NEW_INDEX *and* echo it. The loop
# reads the global (no fork); tests still capture via $(...). This matters
# for latency: calling a mover as $(move_selection ...) forks a subshell per
# keypress, and the backgrounded view-redirect started inside it can keep
# the command-substitution pipe open until it finishes — reintroducing the
# very stall we removed. Reading the global sidesteps the subshell entirely.
NAV_NEW_INDEX=0

move_selection() {
    local direction="$1" # "up" or "down"
    local current_index="$2"
    local new_index

    if [[ "$direction" == "down" ]]; then
        new_index=$((current_index + 1))
        [[ $new_index -ge ${#SESSION_IDS[@]} ]] && new_index=0
    else
        new_index=$((current_index - 1))
        [[ $new_index -lt 0 ]] && new_index=$((${#SESSION_IDS[@]} - 1))
        [[ $new_index -lt 0 ]] && new_index=0
    fi

    if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
        local new_session="${SESSION_IDS[$new_index]}"
        set_nav_selected "$new_session"
        signal_view_update_async
    fi

    NAV_NEW_INDEX="$new_index"
    echo "$new_index"
}

# Go to first session
go_first() {
    if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
        set_nav_selected "${SESSION_IDS[0]}"
        signal_view_update_async
    fi
    NAV_NEW_INDEX=0
    echo 0
}

# Go to last session
go_last() {
    if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
        local last_index=$((${#SESSION_IDS[@]} - 1))
        set_nav_selected "${SESSION_IDS[$last_index]}"
        signal_view_update_async
        NAV_NEW_INDEX="$last_index"
        echo "$last_index"
    else
        NAV_NEW_INDEX=0
        echo 0
    fi
}

# ============================================================================
# Main Loop
# ============================================================================

# Hand the screen back to the list after an interactive sub-flow (fzf, a
# y/n prompt, session-add) has drawn over it.
# The full return-from-sub-flow sequence, in the one order that is correct.
#
# Every interactive sub-flow (a picker, a y/n prompt, the help screen) leaves
# three things wrong behind it: keys the user typed while it was busy are
# sitting in the input buffer, echo is back on because the sub-flow re-enabled
# it, and the terminal may have been resized while another program owned the
# screen. Each handler used to fix some subset of those in its own order — the
# restore key flushed nothing, so a stray keypress during a restore was acted
# on afterwards, and the help screen never dropped the width cache. Doing all
# three in one place is what stops the next sub-flow from inheriting a
# different set of leftovers.
#
# Note there is no `clear` here. Clearing blanks the screen until the next
# render_list — a visible flash on every n/f/N/D/r — and is not needed:
# render_list homes the cursor, writes every line with a clear-to-end-of-line
# and finishes with clear-to-end-of-screen, so it overwrites whatever the
# sub-flow left behind. Dropping the cached width is all the redraw needs.
_return_from_subflow() {
    # Drop anything typed while the sub-flow held the screen. -t 0.01 makes
    # this a drain, not a wait.
    read -rsn100 -t 0.01 _ 2>/dev/null || true
    nav_echo_off
    _reset_width_cache
}

# Turn OFF terminal echo so navigation keys (j/k/g/G/…) don't paint their
# literal characters onto the list before we redraw. read -rsn1 still
# receives the key; only the terminal's own echoing is suppressed. Restored
# on exit so the shell we return to behaves normally. Interactive sub-flows
# (fzf, y/n prompts) re-enable echo themselves and call nav_echo_off again
# on return.
nav_echo_off() { stty -echo 2>/dev/null || true; }
nav_echo_on() { stty echo 2>/dev/null || true; }

main_loop() {
    # Keep the terminal quiet during navigation, and always hand it back in a
    # sane state (echo on, cursor visible) however the loop ends.
    #
    # Arm the restore FIRST. With the order reversed, a signal arriving in the
    # gap between disabling echo and installing the handler would leave the
    # user at a shell that no longer echoes what they type.
    nav_install_signal_traps 'nav_echo_on; printf "\033[?25h" 2>/dev/null || true' navigator-list.sh
    nav_echo_off

    # Take ownership of the shared state files. The newest list pane wins:
    # this pane is the one attached to the Navigator the user is looking at,
    # so any older loop still running from a previous Navigator must stop
    # writing the cursor. Claiming here (not at source time) keeps one-shot
    # helpers that source this file from stealing the claim.
    claim_nav_state

    # Initial build is synchronous so the first frame is correct, then seed
    # the cache from it. From here on the refresh tick only loads the cache
    # and rebuilds in the background, never on the input thread.
    build_session_list
    _serialize_session_state >"$(_session_cache_file)" 2>/dev/null || true

    # Validate current selection - clear if session no longer exists
    local current_selected
    current_selected=$(get_nav_selected)
    if [[ -n "$current_selected" ]]; then
        local found=0
        for id in "${SESSION_IDS[@]:-}"; do
            [[ "$id" == "$current_selected" ]] && { found=1; break; }
        done
        if [[ $found -eq 0 ]]; then
            # Selected session no longer exists, clear selection
            set_nav_selected ""
        fi
    fi

    # Get initial selection
    local selected_index
    selected_index=$(get_selection_index)

    # Set initial selection if not set or invalid
    if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
        current_selected=$(get_nav_selected)
        if [[ -z "$current_selected" ]]; then
            set_nav_selected "${SESSION_IDS[0]}"
            signal_view_update
        fi
    fi

    # Initial clear and hide cursor during rendering
    clear

    while true; do
        # render_list handles cursor positioning internally
        render_list "$selected_index"

        # Wait for input with timeout (short tick so the spinner turns).
        # nav_read_key guards against the orphaned-terminal busy-loop: rc 2
        # means the pane is gone and we must exit rather than spin forever.
        local key="" read_rc=0 doomed="" doomed_row="" queue_rc=0
        nav_read_key key "$TICK_INTERVAL" || read_rc=$?
        [[ $read_rc -eq 2 ]] && exit 0
        if [[ $read_rc -eq 0 ]]; then
            case "$key" in
                j | $'\x1b')
                    # Handle arrow keys
                    if [[ "$key" == $'\x1b' ]]; then
                        read -rsn2 -t 0.1 arrow || true
                        case "$arrow" in
                            '[B') key="j" ;; # Down
                            '[A') key="k" ;; # Up
                            *) continue ;;
                        esac
                    fi
                    if [[ "$key" == "j" ]]; then
                        move_selection "down" "$selected_index" >/dev/null
                        selected_index=$NAV_NEW_INDEX
                    fi
                    ;;
                k)
                    move_selection "up" "$selected_index" >/dev/null
                    selected_index=$NAV_NEW_INDEX
                    ;;
                g)
                    go_first >/dev/null
                    selected_index=$NAV_NEW_INDEX
                    ;;
                G)
                    go_last >/dev/null
                    selected_index=$NAV_NEW_INDEX
                    ;;
                '') # Enter key - same as i
                    focus_view
                    ;;
                i)
                    focus_view
                    ;;
                n)
                    add_session_inline
                    _return_from_subflow
                    # The row is already in the arrays (the sub-flow seated
                    # it), so the selection lookup finds the new session and
                    # the cursor stays on it. The background rebuild replaces
                    # the placeholder row with the real one.
                    _settle_after_change "$(get_selection_index)" >/dev/null
                    selected_index=$NAV_NEW_INDEX
                    ;;
                f)
                    fork_session_here
                    _return_from_subflow
                    # The row is already in the arrays (the sub-flow seated
                    # it), so the selection lookup finds the new session and
                    # the cursor stays on it. The background rebuild replaces
                    # the placeholder row with the real one.
                    _settle_after_change "$(get_selection_index)" >/dev/null
                    selected_index=$NAV_NEW_INDEX
                    ;;
                N)
                    new_session_pick_dir
                    _return_from_subflow
                    # The row is already in the arrays (the sub-flow seated
                    # it), so the selection lookup finds the new session and
                    # the cursor stays on it. The background rebuild replaces
                    # the placeholder row with the real one.
                    _settle_after_change "$(get_selection_index)" >/dev/null
                    selected_index=$NAV_NEW_INDEX
                    ;;
                D)
                    doomed=$(get_nav_selected)
                    if [[ -n "$doomed" ]] && confirm_delete_selected "$doomed"; then
                        # Show the row as deleting before running the delete,
                        # so the list says what is happening rather than the
                        # row simply ceasing to exist.
                        _mark_session_deleting "$doomed" || true
                        doomed_row="$MARKED_ROW_BEFORE"
                        render_list "$selected_index"
                        if execute_delete "$doomed"; then
                            # Take the row out of the list we already have
                            # instead of rebuilding: the rebuild costs over a
                            # second, and for a delete we know what changed.
                            _forget_session_row "$doomed" || true
                        elif [[ -n "$doomed_row" ]]; then
                            _restore_session_row "$doomed" "$doomed_row" || true
                        fi
                        _settle_after_change "$selected_index" >/dev/null
                        selected_index=$NAV_NEW_INDEX
                    fi
                    _return_from_subflow
                    ;;
                r)
                    # Restore selected dormant session
                    restore_selected || true
                    _return_from_subflow
                    _settle_after_change "$selected_index" >/dev/null
                    selected_index=$NAV_NEW_INDEX
                    ;;
                $'\t') # Tab key
                    switch_to_tile || true
                    ;;
                t)
                    switch_to_tail || true
                    ;;
                w)
                    # Foreground sub-flow in this pane. On return, the cursor
                    # follows whatever the queue left in the selection file,
                    # so the row the user picked there is the row under the
                    # cursor here — screen and state agree.
                    queue_rc=0
                    switch_to_queue || queue_rc=$?
                    _return_from_subflow
                    if [[ $queue_rc -eq $QUEUE_EXIT_QUIT ]]; then
                        quit_navigator
                    fi
                    # The list arrays are as old as the moment w was pressed;
                    # the cache may have moved on (a rebuild finished, a
                    # session was added from the CLI) and the queue can have
                    # picked a row the arrays do not hold yet. Reload before
                    # looking the selection up, then make sure the view pane
                    # shows the same session the cursor is on.
                    _load_session_state || true
                    selected_index=$(get_selection_index)
                    signal_view_update_async
                    ;;
                '?')
                    show_help
                    _return_from_subflow
                    ;;
                q | Q)
                    quit_navigator
                    ;;
            esac
        else
            # Timeout tick - advance the spinner; refresh the session list
            # every TICKS_PER_REFRESH ticks. The refresh must NOT build inline
            # (seconds of stat/grep would stall the read loop and swallow j/k):
            # load the last cached result instantly, then kick ONE background
            # rebuild whose fresh cache the next refresh swaps in.
            SPIN_TICK=$(((SPIN_TICK + 1) % 1000000))
            # Every tick, not just refresh ticks: a redirect dropped by the
            # coalescer should reach the view pane in a quarter second, not
            # wait two for the next rebuild.
            _flush_pending_view_signal
            if [[ $((SPIN_TICK % TICKS_PER_REFRESH)) -ne 0 ]]; then
                continue
            fi
            _load_session_state || build_session_list
            _spawn_background_rebuild

            # A view (Tile/Tail) may have moved the selection while this loop
            # sat detached; it writes the file, not our index. Follow it, or
            # the highlight and the id D/Enter act on disagree.
            local synced
            synced=$(get_nav_selected)
            if [[ -n "$synced" && "${SESSION_IDS[$selected_index]:-}" != "$synced" ]]; then
                selected_index=$(get_selection_index)
            fi

            # Clamp selection
            if [[ $selected_index -ge ${#SESSION_IDS[@]} ]]; then
                selected_index=$((${#SESSION_IDS[@]} - 1))
                [[ $selected_index -lt 0 ]] && selected_index=0
                if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
                    set_nav_selected "${SESSION_IDS[$selected_index]}"
                fi
            fi
        fi
    done
}
