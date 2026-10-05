#!/usr/bin/env bash
# session-rename.sh - `tower rename`: set or clear the Navigator display name
# of a Tower session (value/001-tower-session-cli, UC1).
#
#   tower rename <name> [--session <id>]
#   tower rename --clear [--session <id>]
#
# Without --session the target is the Tower session whose pane this runs in,
# so from inside a session (where a skill calls it) no id is needed. On
# success the session id is the only thing on stdout. Exit 2 for a usage
# error, 1 when the session is not registered. Never asks a question.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="session-rename.sh"
source "$SCRIPT_DIR/../lib/common.sh"
set +e

usage() {
    cat >&2 <<'EOF'
Usage: tower rename <name> [--session <id>]
       tower rename --clear [--session <id>]
EOF
}

NAME=""
CLEAR=0
SESSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --clear) CLEAR=1 ;;
        --session)
            if [[ -z "${2:-}" ]]; then
                handle_error "--session needs a session id"
                usage
                exit 2
            fi
            SESSION="$2"
            shift
            ;;
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
            if [[ -n "$NAME" ]]; then
                handle_error "Only one name can be given (got '$NAME' and '$1')"
                exit 2
            fi
            NAME="$1"
            ;;
    esac
    shift
done

if [[ $CLEAR -eq 1 && -n "$NAME" ]]; then
    handle_error "--clear and a name cannot be combined"
    exit 2
fi
if [[ $CLEAR -eq 0 && -z "${NAME//[[:space:]]/}" ]]; then
    handle_error "A name is required (or --clear to remove the current one)"
    usage
    exit 2
fi

if [[ -z "$SESSION" ]]; then
    if ! SESSION=$(current_tower_session); then
        handle_error "Not inside a Tower session: use --session <id> (see 'tower list')"
        exit 2
    fi
fi
# Accept the bare uuid too, as `tower add` does for ids.
[[ "$SESSION" == tower_* ]] || SESSION="tower_${SESSION}"

if ! has_metadata "$SESSION"; then
    handle_error "Session not registered: $SESSION"
    exit 1
fi

if [[ $CLEAR -eq 1 ]]; then
    set_session_name "$SESSION" "" || exit 1
    handle_success "Name cleared for ${SESSION#tower_}" >&2
else
    set_session_name "$SESSION" "$NAME" || exit 1
    handle_success "Renamed ${SESSION#tower_}: $NAME" >&2
fi
echo "$SESSION"
