#!/usr/bin/env bash
# shellcheck shell=bash
# nav-view-signal.sh - Telling the view pane the selection moved.
#
# Owns the view redirect and the coalescing that keeps cursor movement from
# waiting on a tmux round-trip.

# Redirect the view pane to the currently-selected session.
#
# The view pane blocks inside `session_tmux attach-session`, so it cannot
# switch itself — switch-client reaches into that already-attached nested
# client and points it at the new session without a detach/re-attach cycle.
# This is load-bearing for correctness, not just speed: without it the view
# stays stuck on whatever it first attached to.
#
# Why it must not run inline: the list and view share ONE tmux server, a
# single event loop. Run synchronously in move_selection, each keypress
# waits on this whole round-trip (display-message + switch-client + wait-for)
# AND on the view repainting the freshly-switched session — that coupling is
# the cursor-movement lag. So we NEVER call this inline; movers call
# signal_view_update_async, which detaches it completely (see below).
signal_view_update() {
    # The redirect itself lives in common.sh so the queue mode, which runs as
    # its own process in this pane, can drive the same view pane.
    nav_redirect_view
}

# Fire the view redirect fully detached so cursor movement never waits on it.
#
# Two things keep the list loop from blocking:
#  1. The job runs in the background (&) with its own stdout/stderr sent to
#     /dev/null, so even a mover called inside $(...) does not keep the
#     command-substitution pipe open waiting for it.
#  2. We coalesce on a single PID: while one redirect is still in flight we
#     don't spawn another. A fast j/k burst therefore fires at most one
#     switch per completed redirect, and the LAST selection always wins
#     because signal_view_update re-reads the state file at the moment it
#     runs — set_nav_selected has already recorded the newest value.
_VIEW_SIGNAL_PID=""
_VIEW_SIGNAL_PENDING=0
signal_view_update_async() {
    if [[ -n "$_VIEW_SIGNAL_PID" ]] && kill -0 "$_VIEW_SIGNAL_PID" 2>/dev/null; then
        # One is already in flight. Remember that the selection moved again
        # so the trailing edge still gets sent: the running redirect re-reads
        # the state file when it starts, so it may have been launched before
        # this newest move and would otherwise leave the view pane waiting on
        # its own 0.1s poll to notice.
        _VIEW_SIGNAL_PENDING=1
        return
    fi
    _VIEW_SIGNAL_PENDING=0
    { signal_view_update; } >/dev/null 2>&1 &
    _VIEW_SIGNAL_PID=$!
}

# Re-fire the redirect that was coalesced away, once the in-flight one is
# done. Called from the tick loop, where a stall costs nothing.
_flush_pending_view_signal() {
    ((_VIEW_SIGNAL_PENDING)) || return 0
    [[ -n "$_VIEW_SIGNAL_PID" ]] && kill -0 "$_VIEW_SIGNAL_PID" 2>/dev/null && return 0
    signal_view_update_async
}
