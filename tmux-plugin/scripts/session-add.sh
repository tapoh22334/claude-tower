#!/usr/bin/env bash
# session-add.sh - Unified add/new flow.
# Pick an existing Claude session (or [new]) via $TOWER_FINDER (fzf default,
# numbered fallback), register it, and start it in tmux.
# --print-id: print the tower_<uuid> id on stdout on success (for Navigator).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

PRINT_ID=0
[[ "${1:-}" == "--print-id" ]] && PRINT_ID=1

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

# stdin: id \t mtime \t cwd  ->  "shortid  ~/dir/tail  (2m ago)"
format_candidate_lines() {
    local id mtime cwd short reltime
    while IFS=$'\t' read -r id mtime cwd; do
        short="${id:0:7}"
        reltime=$(format_relative_time "$mtime")
        # Abbreviate $HOME as ~
        case "$cwd" in
            "$HOME"*) cwd="~${cwd#"$HOME"}" ;;
        esac
        printf '%s  %s  (%s)\n' "$short" "$cwd" "$reltime"
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
            echo "TOWER_FINDER command not found: $finder_bin (falling back to numbered picker)" >&2
        fi
        pick_with_numbers
    fi
}

# Resolve a picked display line back to the full session id by short-id prefix.
# Fails on multiple matches: two UUIDs sharing a 7-hex prefix must not
# silently resolve to the wrong session.
# $1 = picked line; candidate list on stdin (id \t mtime \t cwd)
resolve_picked_id() {
    local picked="$1"
    local short="${picked%%  *}"
    local id _rest match=""
    while IFS=$'\t' read -r id _rest; do
        if [[ "$id" == "$short"* ]]; then
            if [[ -n "$match" ]]; then
                handle_error "Ambiguous selection"
                return 1
            fi
            match="$id"
        fi
    done
    [[ -n "$match" ]] || return 1
    echo "$match"
}

# Prompt for the new-session directory. Default: caller pane cwd (or $PWD).
# "+" enters the worktree helper (a plain `git worktree add` wrapper —
# Tower does not track or clean up worktrees).
prompt_new_directory() {
    local default_dir="${1:-$PWD}"
    local dir
    printf 'Directory [%s] ("+" = new git worktree): ' "$default_dir" >&2
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
            echo "Not a git repository: $repo" >&2
            return 1
        fi
        printf 'Worktree path: ' >&2
        read -r wt_path </dev/tty || return 1
        [[ -n "$wt_path" ]] || return 1
        printf 'Branch [tower/%s]: ' "$(basename -- "$wt_path")" >&2
        read -r branch </dev/tty || return 1
        branch="${branch:-tower/$(basename -- "$wt_path")}"
        if ! git -C "$repo" worktree add -b "$branch" "$wt_path" >&2; then
            echo "git worktree add failed" >&2
            return 1
        fi
        echo "$wt_path"
        return 0
    fi
    # Expand leading ~
    dir="${dir/#\~/$HOME}"
    echo "$dir"
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
    start_claude_session "tower_${uuid}" "$dir" "new" || return 1
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
    start_claude_session "tower_${claude_id}" "$cwd" "resume" || return 1
    save_metadata "tower_${claude_id}"
    [[ "$PRINT_ID" -eq 1 ]] && echo "tower_${claude_id}"
    return 0
}

main() {
    local candidates picked
    candidates=$(list_addable_sessions)

    picked=$(
        {
            echo "$NEW_SENTINEL"
            [[ -n "$candidates" ]] && format_candidate_lines <<<"$candidates"
        } | run_picker
    ) || return 1
    [[ -n "$picked" ]] || return 1

    if [[ "$picked" == "$NEW_SENTINEL" ]]; then
        start_new_session
    else
        local claude_id
        claude_id=$(resolve_picked_id "$picked" <<<"$candidates") || {
            handle_error "Could not resolve selection"
            return 1
        }
        add_existing_session "$claude_id"
    fi
}

main "$@"
