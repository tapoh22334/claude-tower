#!/usr/bin/env bash
# navigator-list.sh - Left pane: Session list with vim-style navigation
#
# This script runs in the left pane of Navigator.
# It displays the session list and handles navigation keys.
# When switching sessions, it updates the state file and signals the right pane.
#
# The implementation lives in ../lib/nav/, one file per responsibility; this
# file is only the entry point that wires them together in dependency order.

# Use pipefail but handle errors gracefully instead of exiting
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Identify which Navigator pane this loop is running in, before common.sh is
# sourced — the state accessors there consult it to decide whether this
# process is still the live list pane or one that outlived its Navigator.
# Empty outside tmux (running the script directly), which leaves the
# ownership check inert and the old unguarded behaviour in place.
TOWER_NAV_PANE="${TMUX_PANE:-}"
export TOWER_NAV_PANE

source "$SCRIPT_DIR/../lib/common.sh"

# Error handler - log and continue instead of exiting
handle_script_error() {
    local line="$1"
    error_log "navigator-list.sh: Error at line $line"
    # Don't exit - the main loop will continue
}

trap 'handle_script_error $LINENO' ERR

# shellcheck source=../lib/nav/nav-render.sh
source "$SCRIPT_DIR/../lib/nav/nav-render.sh"
# shellcheck source=../lib/nav/nav-build.sh
source "$SCRIPT_DIR/../lib/nav/nav-build.sh"
# shellcheck source=../lib/nav/nav-cache.sh
source "$SCRIPT_DIR/../lib/nav/nav-cache.sh"
# shellcheck source=../lib/nav/nav-view-signal.sh
source "$SCRIPT_DIR/../lib/nav/nav-view-signal.sh"
# shellcheck source=../lib/nav/nav-optimistic.sh
source "$SCRIPT_DIR/../lib/nav/nav-optimistic.sh"
# shellcheck source=../lib/nav/nav-actions.sh
source "$SCRIPT_DIR/../lib/nav/nav-actions.sh"
# shellcheck source=../lib/nav/nav-loop.sh
source "$SCRIPT_DIR/../lib/nav/nav-loop.sh"

# Only start the render loop when executed directly, so tests can source
# this file to reach its functions.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_loop
fi
