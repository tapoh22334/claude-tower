#!/usr/bin/env bash
# project-new.sh - `tower project new`: create a project directory, run
# `git init`, and start its first session (value/001-tower-session-cli, UC3).
#
#   tower project new <name> [--in <parent>] [--prompt <text> | --prompt-file <path|->]
#
# The parent defaults to ~/working (TOWER_PROJECTS_DIR overrides). Nothing is
# created when the target already exists or the name is unsafe; when
# `git init` fails the directory is left for inspection and no session is
# started. On success the new session id is the only thing on stdout.
# Exit 2 for a usage error, 1 for a runtime failure. Never asks a question.
# GitHub-side creation is deliberately not done here (publishing is the
# person's call).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOWER_SCRIPT_NAME="project-new.sh"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/session-open.sh"
set +e

usage() {
    cat >&2 <<'EOF'
Usage: tower project new <name> [--in <parent>] [--prompt <text> | --prompt-file <path|->]
EOF
}

NAME=""
PARENT="${TOWER_PROJECTS_DIR:-$HOME/working}"
PROMPT=""
PROMPT_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --in)
            if [[ -z "${2:-}" ]]; then
                handle_error "--in needs a parent directory"
                exit 2
            fi
            PARENT="$2"
            shift
            ;;
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
            if [[ -n "$NAME" ]]; then
                handle_error "Only one project name can be given (got '$NAME' and '$1')"
                exit 2
            fi
            NAME="$1"
            ;;
    esac
    shift
done

if [[ -z "$NAME" ]]; then
    handle_error "A project name is required"
    usage
    exit 2
fi
# A name is one path component: no separators, and nothing that reads as an
# option or a hidden/parent entry.
if [[ "$NAME" == */* || "$NAME" == -* || "$NAME" == .* ]]; then
    handle_error "Invalid project name: $NAME (no '/', and it cannot start with '-' or '.')"
    exit 2
fi
if [[ -n "$PROMPT" && -n "$PROMPT_FILE" ]]; then
    handle_error "--prompt and --prompt-file cannot be combined"
    exit 2
fi

PARENT="${PARENT/#\~/$HOME}"
if [[ ! -d "$PARENT" ]]; then
    handle_error "Parent directory not found: $PARENT"
    exit 1
fi
TARGET="$PARENT/$NAME"
if [[ -e "$TARGET" ]]; then
    handle_error "Already exists: $TARGET"
    exit 1
fi

# Everything is validated; now take the prompt (stdin may be involved).
PROMPT_TMP=$(prompt_to_file "$PROMPT" "$PROMPT_FILE") || exit 1

if ! mkdir -- "$TARGET"; then
    handle_error "Could not create directory: $TARGET"
    [[ -n "$PROMPT_TMP" ]] && rm -f "$PROMPT_TMP"
    exit 1
fi
if ! git init -q -- "$TARGET" >&2; then
    handle_error "git init failed in $TARGET (directory left in place)"
    [[ -n "$PROMPT_TMP" ]] && rm -f "$PROMPT_TMP"
    exit 1
fi
handle_success "Created $TARGET (git initialized)" >&2

open_session_in_dir "$TARGET" "$PROMPT_TMP" || exit 1
