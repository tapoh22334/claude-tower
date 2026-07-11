#!/usr/bin/env bash
# claude-sessions.sh - Derive session facts from Claude Code's own transcripts
#
# Claude Code writes transcripts to:
#   $CLAUDE_PROJECTS_DIR/<slug>/<sessionId>.jsonl        top-level sessions
#   $CLAUDE_PROJECTS_DIR/<slug>/<sessionId>/subagents/   subagent transcripts
#
# Slug dirs start with "-" (cwd starts with "/"), so every grep/stat on
# these paths must use absolute paths and the "--" separator.
# grep -o / -m are GNU extensions; keep flags separated (no -om1).

CLAUDE_PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
TOWER_BUSY_WINDOW="${TOWER_BUSY_WINDOW:-45}"

# Find the transcript for a Claude session ID (without tower_ prefix)
# Output: absolute path. Returns 1 if not found.
find_session_jsonl() {
    local session_id="$1"
    local f
    for f in "$CLAUDE_PROJECTS_DIR"/*/"${session_id}".jsonl; do
        [[ -f "$f" ]] || continue
        echo "$f"
        return 0
    done
    return 1
}

# First "cwd" value in a transcript (= launch dir; matches --resume scope
# and the slug). cwd can change mid-session via cd; first occurrence wins.
# Returns 1 if the transcript has no cwd line (session died at startup).
get_session_cwd() {
    local jsonl="$1"
    [[ -f "$jsonl" ]] || return 1
    local match
    match=$(grep -o -m 1 '"cwd":"[^"]*"' -- "$jsonl" 2>/dev/null) || return 1
    match="${match#\"cwd\":\"}"
    echo "${match%\"}"
}

# Session has at least one real message (filters empty shells)
session_has_messages() {
    local jsonl="$1"
    grep -q -m 1 -E '"type":"(user|assistant)"' -- "$jsonl" 2>/dev/null
}

# Newest activity epoch across the transcript, its subagents, and its
# background-task outputs. Background Agent runs write outside the projects
# dir (under $TMPDIR/claude-<uid>/<slug>/<id>/tasks/) while the parent
# transcript idles — checking only the jsonl would show a working session
# as idle.
get_session_activity() {
    local jsonl="$1"
    local latest=0 t f
    t=$(stat -c %Y -- "$jsonl" 2>/dev/null) && ((t > latest)) && latest=$t

    local session_id dir slug
    dir=$(dirname -- "$jsonl")
    session_id=$(basename -- "$jsonl" .jsonl)
    slug=$(basename -- "$dir")

    for f in "${dir}/${session_id}/subagents"/*.jsonl; do
        [[ -f "$f" ]] || continue
        t=$(stat -c %Y -- "$f" 2>/dev/null) && ((t > latest)) && latest=$t
    done

    for f in "${TMPDIR:-/tmp}/claude-$(id -u)/${slug}/${session_id}/tasks"/*.output; do
        [[ -f "$f" ]] || continue
        t=$(stat -c %Y -- "$f" 2>/dev/null) && ((t > latest)) && latest=$t
    done

    echo "$latest"
}

# Activity within TOWER_BUSY_WINDOW seconds?
# Known limits (documented in spec): session start touches the jsonl
# (45s false-busy), and tool runs longer than the window read as idle.
is_session_busy() {
    local jsonl="$1"
    local activity now
    activity=$(get_session_activity "$jsonl")
    now=$(date +%s)
    ((now - activity <= TOWER_BUSY_WINDOW))
}

# Display state for the Navigator list.
#   busy    - tmux session exists, activity within window
#   active  - tmux session exists
#   dormant - registered, resumable (jsonl + cwd exist)
#   dead    - registered but cwd dir is gone -> --resume can never find it
#   lost    - registered but transcript gone (Claude's ~30-day cleanup)
#   ""      - not registered, no tmux
get_display_state() {
    local session_id="$1"
    local claude_id="${session_id#tower_}"
    local jsonl

    if session_tmux has-session -t "$session_id" 2>/dev/null; then
        if jsonl=$(find_session_jsonl "$claude_id") && is_session_busy "$jsonl"; then
            echo "busy"
        else
            echo "active"
        fi
        return 0
    fi

    has_metadata "$session_id" || return 0

    if ! jsonl=$(find_session_jsonl "$claude_id"); then
        echo "lost"
        return 0
    fi

    local cwd
    cwd=$(get_session_cwd "$jsonl" || true)
    if [[ -z "$cwd" || ! -d "$cwd" ]]; then
        echo "dead"
    else
        echo "dormant"
    fi
}

# Candidate sessions for the add flow.
# Output: <sessionId>\t<mtime_epoch>\t<cwd>   newest first
# Excludes: registered, empty shells, tmp-internal, missing-cwd sessions.
list_addable_sessions() {
    local f session_id cwd mtime
    for f in "$CLAUDE_PROJECTS_DIR"/*/*.jsonl; do
        [[ -f "$f" ]] || continue
        session_id=$(basename -- "$f" .jsonl)
        [[ "$session_id" =~ ^[0-9a-f-]{36}$ ]] || continue
        has_metadata "tower_${session_id}" && continue
        session_has_messages "$f" || continue
        cwd=$(get_session_cwd "$f") || continue
        [[ -n "$cwd" && -d "$cwd" ]] || continue
        case "$cwd" in
            "${TMPDIR:-/tmp}"/*) continue ;;
        esac
        mtime=$(stat -c %Y -- "$f" 2>/dev/null) || continue
        printf '%s\t%s\t%s\n' "$session_id" "$mtime" "$cwd"
    done | sort -t "$(printf '\t')" -k2,2nr
}

# "2m ago" / "3h ago" / "5d ago"
format_relative_time() {
    local epoch="$1" now diff
    now=$(date +%s)
    diff=$((now - epoch))
    if ((diff < 3600)); then
        echo "$((diff / 60))m ago"
    elif ((diff < 86400)); then
        echo "$((diff / 3600))h ago"
    else
        echo "$((diff / 86400))d ago"
    fi
}
