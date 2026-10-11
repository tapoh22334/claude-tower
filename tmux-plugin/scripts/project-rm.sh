#!/usr/bin/env bash
# project-rm.sh - `tower project rm`: take a project off the Navigator list
# (value/002-project-rows). Only when Tower has no session there; the
# directory itself is never touched. Prints the canonical path on stdout.
# Exit 2 for a usage error, 1 when the project is not registered or still
# has sessions. Never asks a question.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="project-rm.sh"
source "$SCRIPT_DIR/../lib/common.sh"
set +e

usage() {
    echo "Usage: tower project rm <dir>" >&2
}

DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            handle_error "Unknown option: $1"
            usage
            exit 2
            ;;
        *)
            if [[ -n "$DIR" ]]; then
                handle_error "Only one directory can be given (got '$DIR' and '$1')"
                exit 2
            fi
            DIR="$1"
            ;;
    esac
    shift
done
if [[ -z "$DIR" ]]; then
    handle_error "A directory is required"
    usage
    exit 2
fi

CANON=$(canon_project_dir "$DIR") || {
    handle_error "Not an absolute path: $DIR"
    exit 2
}
if ! project_registered "$CANON"; then
    handle_error "Project not registered: $CANON"
    exit 1
fi
N=$(project_session_count "$CANON")
if ((N > 0)); then
    handle_error "$N session(s) still registered in $CANON — delete them first"
    exit 1
fi
unregister_project "$CANON" || {
    handle_error "Could not update the project list"
    exit 1
}
# If the Navigator's cursor was on this project, its row is about to go;
# leave the selection empty rather than pointing at a row that no rebuild
# will ever list again.
if [[ "$(get_nav_selected 2>/dev/null)" == "dir:$CANON" ]]; then
    set_nav_selected ""
fi
handle_success "Removed from the Navigator list: $CANON" >&2
echo "$CANON"
