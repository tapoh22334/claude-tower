#!/usr/bin/env bash
# session-open.sh - `tower open`: start a new session in a project directory
# and move the Navigator there, optionally with an initial prompt
# (value/001-tower-session-cli, UC2).
#
#   tower open <dir> [--prompt <text> | --prompt-file <path|->]
#
# The prompt is written to a file the program reads at start, so a summary
# with quotes or newlines is never shell-quoted. The session this is run
# from is left alone. On success the new session id is the only thing on
# stdout. Exit 2 for a usage error, 1 when the directory or prompt file is
# missing. Never asks a question.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="session-open.sh"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/session-open.sh"
set +e

usage() {
    cat >&2 <<'EOF'
Usage: tower open <dir> [--prompt <text> | --prompt-file <path|->]
EOF
}

DIR=""
PROMPT=""
PROMPT_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt)
            if [[ -z "${2:-}" ]]; then
                handle_error "--prompt needs text"
                exit 2
            fi
            PROMPT="$2"
            shift
            ;;
        --prompt-file)
            if [[ -z "${2:-}" ]]; then
                handle_error "--prompt-file needs a path (or - for stdin)"
                exit 2
            fi
            PROMPT_FILE="$2"
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
if [[ -n "$PROMPT" && -n "$PROMPT_FILE" ]]; then
    handle_error "--prompt and --prompt-file cannot be combined"
    exit 2
fi

# Check the directory before reading the prompt, so a typo in the path does
# not consume stdin first.
if [[ ! -d "${DIR/#\~/$HOME}" ]]; then
    handle_error "Directory not found: $DIR"
    exit 1
fi

PROMPT_TMP=$(prompt_to_file "$PROMPT" "$PROMPT_FILE") || exit 1
open_session_in_dir "$DIR" "$PROMPT_TMP" || exit 1
