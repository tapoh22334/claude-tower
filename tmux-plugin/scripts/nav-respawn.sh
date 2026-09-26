#!/usr/bin/env bash
# nav-respawn.sh PANE_ID — run by the Navigator's pane-died hook
# (setup_pane_auto_restart). Re-runs the dead pane's own command, unless the
# pane has died RESPAWN_MAX times within RESPAWN_WINDOW seconds; then it is
# left dead on screen and the reason is in <script>.stderr.log.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/error-recovery.sh"

pane="${1:-}"
if [[ -z "$pane" ]]; then
    _log_to_file "ERROR" "nav-respawn.sh: no pane id given"
    exit 1
fi

if _respawn_allowed "$pane" "$(date +%s)"; then
    _log_to_file "INFO" "nav-respawn.sh: pane $pane died, respawning"
    # A short pause so a loop that dies on startup does not spin hot.
    sleep 0.5
    # Only a pane that is still dead: a new Navigator on the same socket
    # hands out the same pane ids, and this hook may be left over from the
    # old one.
    if [[ "$(nav_tmux display-message -p -t "$pane" '#{pane_dead}' 2>/dev/null)" == 1 ]]; then
        nav_tmux respawn-pane -k -t "$pane"
    else
        _log_to_file "INFO" "nav-respawn.sh: pane $pane is not dead any more, leaving it"
    fi
else
    _log_to_file "ERROR" "nav-respawn.sh: pane $pane died $RESPAWN_MAX times in ${RESPAWN_WINDOW}s; leaving it dead. See $TOWER_LOG_DIR/navigator-*.stderr.log"
    nav_tmux display-message -d 0 "Navigator pane $pane keeps dying; not restarting. See $TOWER_LOG_DIR/navigator-*.stderr.log" 2>/dev/null || true
fi
