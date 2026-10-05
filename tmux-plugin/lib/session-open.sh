#!/usr/bin/env bash
# session-open.sh - start a new Tower session in a directory, non-interactively,
# optionally handing the program an initial prompt, and point the Navigator
# at it. Shared by `tower open` and `tower project new`
# (value/001-tower-session-cli). Source after lib/common.sh.
#
# Contract for the CLI layer: on success the new tower_<uuid> is the only
# thing on stdout; everything for a person goes to stderr. Nothing here asks
# a question -- a skill drives these with no terminal.

# The prompt ends up as one argv string in the pane's shell, and Linux caps
# a single argument at 128 KiB (MAX_ARG_STRLEN). Refuse well below that so
# the failure is the CLI's, not a silent "argument list too long" in a pane
# nobody is looking at.
PROMPT_MAX_BYTES="${PROMPT_MAX_BYTES:-102400}"

# prompt_to_file TEXT FILE_OR_DASH
# Resolve --prompt / --prompt-file into one temp file and print its path.
# TEXT wins when both are given (the caller rejects that earlier). `-` reads
# stdin. Prints nothing and fails when the source cannot be read, is empty
# (an empty "" positional would still reach the program), or is too large.
prompt_to_file() {
    local text="${1:-}" src="${2:-}" tmp
    if [[ -z "$text" && -z "$src" ]]; then
        echo ""
        return 0
    fi
    ensure_metadata_dir
    tmp=$(mktemp "${TOWER_METADATA_DIR}/.prompt.XXXXXX") || return 1
    if [[ -n "$text" ]]; then
        printf '%s\n' "$text" >"$tmp"
    elif [[ "$src" == "-" ]]; then
        if ! cat >"$tmp"; then
            rm -f "$tmp"
            handle_error "Could not read the prompt from stdin"
            return 1
        fi
    else
        if [[ ! -f "$src" || ! -r "$src" ]] || ! cat -- "$src" >"$tmp" 2>/dev/null; then
            rm -f "$tmp"
            handle_error "Cannot read prompt file: $src"
            return 1
        fi
    fi
    local size
    size=$(wc -c <"$tmp")
    if [[ "$(tr -d '[:space:]' <"$tmp" | wc -c)" -eq 0 ]]; then
        rm -f "$tmp"
        handle_error "The prompt is empty"
        return 1
    fi
    if ((size > PROMPT_MAX_BYTES)); then
        rm -f "$tmp"
        handle_error "The prompt is too large (${size} bytes; limit ${PROMPT_MAX_BYTES}). Put it in a file in the project and refer to it instead"
        return 1
    fi
    echo "$tmp"
}

# open_session_in_dir DIR [PROMPT_TMP]
# Start a brand-new session in DIR. PROMPT_TMP (from prompt_to_file) is moved
# to <id>.prompt in the metadata dir and read by the program as its first
# prompt. Then the Navigator's selection moves to the new session and, when a
# Navigator is running, its view pane follows. The caller's own session is
# never touched. Prints the new id on stdout.
open_session_in_dir() {
    local dir_arg="$1" prompt_tmp="${2:-}"
    local dir="${dir_arg/#\~/$HOME}"
    if [[ -z "$dir" || ! -d "$dir" ]]; then
        handle_error "Directory not found: ${dir_arg:-<empty>}"
        [[ -n "$prompt_tmp" ]] && rm -f "$prompt_tmp"
        return 1
    fi
    dir=$(cd -- "$dir" && pwd -P) || return 1

    local uuid id prompt_file=""
    uuid=$(generate_uuid) || return 1
    id="tower_${uuid}"
    ensure_metadata_dir
    if [[ -n "$prompt_tmp" ]]; then
        prompt_file="${TOWER_METADATA_DIR}/${id}.prompt"
        mv -f "$prompt_tmp" "$prompt_file" || return 1
    fi

    if ! start_claude_session "$id" "$dir" "new" "$prompt_file" >&2; then
        [[ -n "$prompt_file" ]] && rm -f "$prompt_file"
        return 1
    fi
    save_metadata "$id" "" "$dir"

    # The CLI has no TOWER_NAV_PANE, so nav_owns_state leaves it free to
    # write the selection. Writing it is not enough for the view pane to
    # follow, though: only the list loop's own moves signal the view, so an
    # outside writer has to redirect it itself.
    set_nav_selected "$id"
    if nav_tmux has-session -t "$TOWER_NAV_SESSION" 2>/dev/null; then
        nav_redirect_view >/dev/null 2>&1 || true
    fi
    echo "$id"
}
