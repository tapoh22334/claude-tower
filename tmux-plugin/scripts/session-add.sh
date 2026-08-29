#!/usr/bin/env bash
# session-add.sh - Unified add/new flow.
# Pick an existing Claude session (or [new]) via $TOWER_FINDER (fzf default,
# numbered fallback), register it, and start it in tmux.
# --print-id: print the tower_<uuid> id on stdout on success (for Navigator).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

PRINT_ID=0
MODE="pick"      # pick (default) | fork-dir | new-in-dir | in-dir
FORK_DIR=""
TARGET_DIR=""
SESSION_NAME=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --print-id) PRINT_ID=1 ;;
        --fork-dir)
            MODE="fork-dir"
            FORK_DIR="${2:-}"
            shift
            ;;
        --new-in-dir) MODE="new-in-dir" ;;
        -n | --name)
            # Refuse to swallow the next flag as a name: `-n --print-id` would
            # otherwise consume --print-id and leave the caller wondering why
            # nothing was printed.
            if [[ -z "${2:-}" || "${2}" == -* ]]; then
                handle_error "$1 needs a name"
                exit 1
            fi
            SESSION_NAME="$2"
            shift
            ;;
        -*)
            handle_error "Unknown option: $1"
            exit 1
            ;;
        *)
            # A bare path: start a session there without opening the picker.
            # `tower add .` promised this in its help long before anything
            # parsed it — the argument was silently dropped and the picker
            # opened instead.
            if [[ -n "$TARGET_DIR" ]]; then
                handle_error "Only one directory can be given (got '$TARGET_DIR' and '$1')"
                exit 1
            fi
            MODE="in-dir"
            TARGET_DIR="$1"
            ;;
    esac
    shift
done

NEW_SENTINEL="[new]    Start a new session"

generate_uuid() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif [[ -r /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    else
        handle_error "Cannot generate a UUID (need uuidgen or /proc/sys/kernel/random/uuid)"
        return 1
    fi
}

# stdin: id \t mtime \t cwd  ->  "abcd  dirname  first prompt…  (2m ago)"
# The title (first user prompt, via get_session_title) is what tells apart
# sessions sharing a directory; the short id is only for resolution.
format_candidate_lines() {
    local id mtime cwd short reltime dir title
    while IFS=$'\t' read -r id mtime cwd; do
        short="${id:0:4}"
        reltime=$(format_relative_time "$mtime")
        dir=$(basename -- "$cwd")
        title=$(get_session_title "$id" 2>/dev/null) || title=""
        # Keep the line single-line and short; tabs would break resolution.
        # JSON strings carry newlines/tabs as literal \n / \t escapes.
        title="${title//\\n/ }"
        title="${title//\\t/ }"
        title="${title//$'\t'/ }"
        [[ ${#title} -gt 48 ]] && title="${title:0:47}…"
        printf '%s  %-18s %s  (%s)\n' "$short" "$dir" "$title" "$reltime"
    done
}

# Numbered fallback picker: candidates on stdin, chosen line on stdout.
pick_with_numbers() {
    local -a lines=()
    local line
    while IFS= read -r line; do
        lines+=("$line")
    done
    local i
    for i in "${!lines[@]}"; do
        printf '%2d) %s\n' "$((i + 1))" "${lines[$i]}" >&2
    done
    printf 'Select [1-%d], empty to cancel (install fzf for fuzzy search): ' "${#lines[@]}" >&2
    local choice
    read -r choice </dev/tty || return 1
    [[ "$choice" =~ ^[0-9]+$ ]] || return 1
    ((choice >= 1 && choice <= ${#lines[@]})) || return 1
    echo "${lines[$((choice - 1))]}"
}

# Run the finder (or fallback). Candidates on stdin, selection on stdout.
# Silent fallback to the numbered picker is only for our own fzf default;
# when the user explicitly set TOWER_FINDER and its binary is missing, warn
# loudly on stderr but still fall back so the flow remains usable.
run_picker() {
    local finder="${TOWER_FINDER:-fzf --height=80% --reverse --no-multi}"
    local finder_bin="${finder%% *}"
    if command -v "$finder_bin" >/dev/null 2>&1; then
        eval "$finder"
    else
        if [[ -n "${TOWER_FINDER:-}" ]]; then
            handle_warning "TOWER_FINDER not found: $finder_bin — using the numbered picker"
        fi
        pick_with_numbers
    fi
}

# Resolve a picked display line back to the full session id.
# Candidates and their rendered lines are index-aligned, and the SAME
# rendered text shown to the picker is passed back in — never re-rendered,
# so the short id stays display-only (its length never affects resolution)
# and a relative time ticking over while the user browses cannot break the
# match. Two candidates only clash if their entire rendered lines are
# identical; refuse rather than guess in that case.
# $1 = picked line; $2 = rendered lines (as shown); candidates on stdin
resolve_picked_id() {
    local picked="$1" rendered="$2"
    local -a ids=() lines=()
    local line id _rest
    while IFS=$'\t' read -r id _rest; do
        ids+=("$id")
    done
    while IFS= read -r line; do
        lines+=("$line")
    done <<<"$rendered"
    local i match=""
    for i in "${!lines[@]}"; do
        if [[ "${lines[$i]}" == "$picked" ]]; then
            if [[ -n "$match" ]]; then
                handle_error "Ambiguous selection"
                return 1
            fi
            match="${ids[$i]}"
        fi
    done
    [[ -n "$match" ]] || return 1
    echo "$match"
}

# Prompt for the new-session directory. Default: caller pane cwd (or $PWD).
# A path that doesn't exist is offered for creation (mkdir -p). "+" enters
# the worktree helper (a plain `git worktree add` wrapper — Tower does not
# track or clean up worktrees).
prompt_new_directory() {
    local default_dir="${1:-$PWD}"
    local dir
    printf 'Directory [%s] ("+" = new git worktree, new path = create): ' "$default_dir" >&2
    read -r dir </dev/tty || return 1
    if [[ -z "$dir" ]]; then
        echo "$default_dir"
        return 0
    fi
    if [[ "$dir" == "+" ]]; then
        local repo wt_path branch
        printf 'Repository [%s]: ' "$default_dir" >&2
        read -r repo </dev/tty || return 1
        repo="${repo:-$default_dir}"
        if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
            handle_error "Not a git repository: $repo"
            return 1
        fi
        printf 'Worktree path: ' >&2
        read -r wt_path </dev/tty || return 1
        [[ -n "$wt_path" ]] || return 1
        wt_path="${wt_path/#\~/$HOME}"
        # A relative path here is taken against the repo, not the caller's cwd,
        # and "../.." must not walk out of it: `git worktree add` will happily
        # create a tree anywhere on disk, which is not what "make me a worktree
        # of this repo" means to the person typing it.
        [[ "$wt_path" == /* ]] || wt_path="${repo%/}/$wt_path"
        if ! validate_path_within "$wt_path" "$repo"; then
            handle_error "Worktree path must stay inside $repo"
            return 1
        fi
        printf 'Branch [tower/%s]: ' "${wt_path##*/}" >&2
        read -r branch </dev/tty || return 1
        branch="${branch:-tower/${wt_path##*/}}"
        # Branch names go to `git worktree add -b`; git rejects a bad one, but
        # it also treats a leading dash as an option, so refuse those outright.
        if [[ "$branch" == -* ]]; then
            handle_error "Branch name cannot start with '-' (git would read it as an option): $branch"
            return 1
        fi
        if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
            handle_error "Not a valid git branch name: $branch (no spaces, '..', '~', '^', ':' or a trailing '.')"
            return 1
        fi
        if ! git -C "$repo" worktree add -b "$branch" "$wt_path" >&2; then
            handle_error "git worktree add failed"
            return 1
        fi
        echo "$wt_path"
        return 0
    fi
    # Expand leading ~
    dir="${dir/#\~/$HOME}"

    # A path that doesn't exist yet is the common "start a brand-new
    # project" case. Offer to create it (mkdir -p is non-destructive: it
    # only adds directories, never touches existing ones). Declining leaves
    # $dir non-existent so start_new_session's own check aborts cleanly.
    if [[ ! -d "$dir" ]]; then
        local reply
        printf 'Directory does not exist. Create %s? [y/N]: ' "$dir" >&2
        read -r reply </dev/tty || return 1
        case "$reply" in
            y | Y | yes | Yes)
                if ! mkdir -p -- "$dir" 2>/dev/null; then
                    handle_error "Could not create directory: $dir"
                    return 1
                fi
                ;;
        esac
    fi
    echo "$dir"
}

# Start a brand-new session in an explicit directory, no prompts.
# Backs both --fork-dir (dir from the caller) and --new-in-dir (dir from
# the project picker).
start_session_in_dir() {
    local dir="$1" name="${2:-}" uuid
    if [[ -z "$dir" || ! -d "$dir" ]]; then
        handle_error "Directory not found: ${dir:-<empty>}"
        return 1
    fi
    uuid=$(generate_uuid) || return 1
    start_claude_session "tower_${uuid}" "$dir" "new" >&2 || return 1
    save_metadata "tower_${uuid}" "$name"
    [[ "$PRINT_ID" -eq 1 ]] && echo "tower_${uuid}"
    return 0
}

start_new_session() {
    local default_dir="${TOWER_ADD_DEFAULT_DIR:-$PWD}"
    local dir uuid name
    dir=$(prompt_new_directory "$default_dir") || return 1
    if [[ ! -d "$dir" ]]; then
        handle_error "Directory not found: $dir"
        return 1
    fi
    printf 'Name (optional): ' >&2
    read -r name </dev/tty || name=""
    uuid=$(generate_uuid) || return 1
    start_claude_session "tower_${uuid}" "$dir" "new" >&2 || return 1
    save_metadata "tower_${uuid}" "$name"
    [[ "$PRINT_ID" -eq 1 ]] && echo "tower_${uuid}"
    return 0
}

add_existing_session() {
    local claude_id="$1"
    if ! [[ "$claude_id" =~ ^[0-9a-f-]{36}$ ]]; then
        handle_error "Invalid session id: $claude_id"
        return 1
    fi
    local jsonl cwd
    if ! jsonl=$(find_session_jsonl "$claude_id"); then
        handle_error "Transcript not found for $claude_id"
        return 1
    fi
    cwd=$(get_session_cwd "$jsonl" || true)
    if [[ -z "$cwd" || ! -d "$cwd" ]]; then
        handle_error "Directory not found: ${cwd:-unknown}"
        return 1
    fi
    start_claude_session "tower_${claude_id}" "$cwd" "resume" >&2 || return 1
    save_metadata "tower_${claude_id}"
    [[ "$PRINT_ID" -eq 1 ]] && echo "tower_${claude_id}"
    return 0
}

main() {
    if [[ "$MODE" == "in-dir" ]]; then
        local dir="${TARGET_DIR/#\~/$HOME}"
        [[ -d "$dir" ]] || { handle_error "Directory not found: $TARGET_DIR"; return 1; }
        dir=$(cd "$dir" && pwd) || return 1
        start_session_in_dir "$dir" "$SESSION_NAME"
        return $?
    fi
    if [[ "$MODE" == "fork-dir" ]]; then
        start_session_in_dir "$FORK_DIR"
        return $?
    fi
    if [[ "$MODE" == "new-in-dir" ]]; then
        local dir
        dir=$(list_project_dirs | run_picker) || return 1
        [[ -n "$dir" ]] || return 1
        start_session_in_dir "$dir"
        return $?
    fi

    local candidates rendered="" picked
    candidates=$(list_addable_sessions)
    # Render exactly once; the picker shows these lines and resolution
    # matches against these same lines.
    if [[ -n "$candidates" ]]; then
        rendered=$(format_candidate_lines <<<"$candidates")
    fi

    picked=$(
        {
            echo "$NEW_SENTINEL"
            # if-form, not `[[ ... ]] &&`: with zero candidates the &&-chain
            # exits 1 and pipefail fails the whole pipeline even though
            # run_picker succeeded, aborting a valid [new] pick.
            if [[ -n "$rendered" ]]; then
                printf '%s\n' "$rendered"
            fi
        } | run_picker
    ) || return 1
    [[ -n "$picked" ]] || return 1

    if [[ "$picked" == "$NEW_SENTINEL" ]]; then
        start_new_session
    else
        local claude_id
        claude_id=$(resolve_picked_id "$picked" "$rendered" <<<"$candidates") || {
            handle_error "Could not resolve selection"
            return 1
        }
        add_existing_session "$claude_id"
    fi
}

main "$@"
