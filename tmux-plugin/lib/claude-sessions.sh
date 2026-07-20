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
CLAUDE_HISTORY_FILE="${CLAUDE_HISTORY_FILE:-$HOME/.claude/history.jsonl}"
CLAUDE_LIVE_SESSIONS_DIR="${CLAUDE_LIVE_SESSIONS_DIR:-$HOME/.claude/sessions}"
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
    elif is_claude_process_alive "$claude_id"; then
        # Running outside Tower's tmux (fork/plain terminal). Resuming
        # would open a second copy of a live session.
        echo "external"
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

# Live claude processes, from Claude's own per-process files
# (~/.claude/sessions/<pid>.json, written by every running claude).
# Output: <sessionId>\t<pid>\t<cwd>   one line per process that is alive.
list_live_claude_processes() {
    local f pid line sid cwd
    for f in "$CLAUDE_LIVE_SESSIONS_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        pid=$(basename -- "$f" .json)
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        kill -0 "$pid" 2>/dev/null || continue
        line=$(head -c 2000 -- "$f" 2>/dev/null) || continue
        sid=$(grep -o '"sessionId":"[^"]*"' <<<"$line") || continue
        sid="${sid#\"sessionId\":\"}"
        sid="${sid%\"}"
        cwd=$(grep -o '"cwd":"[^"]*"' <<<"$line") || cwd=""
        cwd="${cwd#\"cwd\":\"}"
        cwd="${cwd%\"}"
        printf '%s\t%s\t%s\n' "$sid" "$pid" "$cwd"
    done
    return 0
}

# Is a live claude process running this session id (without tower_ prefix)?
is_claude_process_alive() {
    local session_id="$1"
    list_live_claude_processes | grep -q -m 1 "^${session_id}$(printf '\t')"
}

# Count of live claude processes in a directory whose session is NOT
# registered in Tower — forks/sessions started outside Tower's tmux.
count_unregistered_processes_in_dir() {
    local dir="$1"
    local sid _pid cwd n=0
    while IFS=$'\t' read -r sid _pid cwd; do
        [[ "$cwd" == "$dir" ]] || continue
        has_metadata "tower_${sid}" && continue
        n=$((n + 1))
    done < <(list_live_claude_processes)
    echo "$n"
}

# Count of a session's subagents active within TOWER_BUSY_WINDOW.
count_active_subagents() {
    local jsonl="$1"
    local dir session_id now t f n=0
    dir=$(dirname -- "$jsonl")
    session_id=$(basename -- "$jsonl" .jsonl)
    now=$(date +%s)
    for f in "${dir}/${session_id}/subagents"/*.jsonl; do
        [[ -f "$f" ]] || continue
        t=$(stat -c %Y -- "$f" 2>/dev/null) || continue
        if ((now - t <= TOWER_BUSY_WINDOW)); then n=$((n + 1)); fi
    done
    echo "$n"
}

# Known project directories: every distinct transcript cwd that still
# exists, newest transcript activity first. Feeds the new-in-dir picker.
list_project_dirs() {
    local f cwd mtime
    for f in "$CLAUDE_PROJECTS_DIR"/*/*.jsonl; do
        [[ -f "$f" ]] || continue
        cwd=$(get_session_cwd "$f") || continue
        [[ -d "$cwd" ]] || continue
        case "$cwd" in
            "${TMPDIR:-/tmp}"/*) continue ;;
        esac
        mtime=$(stat -c %Y -- "$f" 2>/dev/null) || continue
        printf '%s\t%s\n' "$mtime" "$cwd"
    done | sort -k1,1nr | awk -F'\t' '!seen[$2]++ { print $2 }'
}

# Reduce a raw prompt to the one line worth showing in a list: the first
# sentence, with the JSON escapes Claude stores flattened. Returns 1 for
# prompts that identify nothing — bare slash commands, pastes, and stock
# nudges — so callers can walk to the next prompt instead.
_first_meaningful_sentence() {
    local s="$1"
    # JSON strings carry newlines/tabs as literal \n / \t escapes.
    s="${s//\\n/ }"
    s="${s//\\t/ }"
    s="${s//$'\t'/ }"
    s="${s//\\\"/\"}"
    # Leading whitespace, then a bare slash command (with or without args
    # on the same line) is a command invocation, not a description.
    while [[ "$s" == " "* ]]; do s="${s# }"; done
    [[ "$s" == /* ]] && return 1
    [[ "$s" == "["*"]"* ]] && return 1   # [Image #1], [Pasted text ...]

    # First sentence: split on the first Japanese or ASCII terminator.
    local first="$s"
    local marker
    for marker in '。' '？' '！' '. ' '? ' '! '; do
        if [[ "$first" == *"$marker"* ]]; then
            first="${first%%"$marker"*}"
        fi
    done
    while [[ "$first" == *" " ]]; do first="${first% }"; done

    # Stock nudges carry no information about what the session is for.
    case "$first" in
        continue | Continue | つづき | 続き | 続けて | go | Go | y | yes | ok | OK) return 1 ;;
    esac
    [[ ${#first} -ge 2 ]] || return 1
    printf '%s\n' "$first"
}

# First user prompt of a session, from Claude's own history file
# (~/.claude/history.jsonl: one {"display":...,"sessionId":...} line per
# prompt, oldest first — the same source Claude's resume picker shows).
# Distinguishes sessions that share a cwd. Returns 1 if unknown.
get_session_title() {
    local session_id="$1"
    local line title
    if [[ -f "$CLAUDE_HISTORY_FILE" ]]; then
        # First few prompts of this session, oldest first. The very first
        # one is often a bare slash command or a one-word nudge that says
        # nothing about the work — walk forward until something does.
        while IFS= read -r line; do
            title=$(printf '%s\n' "$line" | grep -o '"display":"[^"]*"') || continue
            title="${title#\"display\":\"}"
            title="${title%\"}"
            title=$(_first_meaningful_sentence "$title") || continue
            printf '%s\n' "$title"
            return 0
        done < <(grep -m 5 -F "\"sessionId\":\"${session_id}\"" -- "$CLAUDE_HISTORY_FILE" 2>/dev/null)
    fi
    # Fallback: first user message in the transcript. Sessions started
    # non-interactively (-p, SDK, subagent relaunch) never reach history.
    local jsonl
    jsonl=$(find_session_jsonl "$session_id") || return 1
    line=$(grep -m 1 '"type":"user"' -- "$jsonl" 2>/dev/null) || return 1
    # content is either a plain string or an array of blocks with "text".
    title=$(printf '%s\n' "$line" | grep -o '"content":"[^"]*"') \
        || title=$(printf '%s\n' "$line" | grep -o '"text":"[^"]*"') \
        || return 1
    title="${title#*:\"}"
    title="${title%\"}"
    [[ -n "$title" ]] || return 1
    _first_meaningful_sentence "$title" || printf '%s\n' "$title"
}

# Display width in terminal cells, and truncation to a cell budget. CJK,
# kana and fullwidth punctuation take two cells each; counting characters
# instead makes a Japanese title overflow the row and wrap onto a second
# line.
#
# Both walk raw UTF-8 bytes rather than using ${#s} / ${s:i:1}: those are
# character-based only under a UTF-8 locale, and Tower runs under whatever
# the terminal has (the test container is ASCII, where bash would see one
# Japanese character as three). Lead byte decides the width: 1- and 2-byte
# sequences are one cell, 3- and 4-byte ones are two. The narrow 3-byte
# exceptions are rare enough in prompts to not warrant a range table.
# $2 < 0 measures; $2 >= 0 truncates to that many cells.
_utf8_walk() {
    local s="$1" max="$2"
    local i=0 n=${#s} lead nbytes cw acc=0 out=""
    local budget=$((max - 1))
    while ((i < n)); do
        printf -v lead '%d' "'${s:$i:1}"
        ((lead < 0)) && lead=$((lead + 256))
        if ((lead < 0x80)); then
            nbytes=1 cw=1
        elif ((lead < 0xE0)); then
            nbytes=2 cw=1
        elif ((lead < 0xF0)); then
            nbytes=3 cw=2
        else
            nbytes=4 cw=2
        fi
        if ((max >= 0 && acc + cw > budget)); then
            printf '%s…\n' "$out"
            return 0
        fi
        ((max >= 0)) && out+="${s:$i:$nbytes}"
        acc=$((acc + cw))
        i=$((i + nbytes))
    done
    if ((max >= 0)); then
        printf '%s\n' "$out"
    else
        echo "$acc"
    fi
}

str_display_width() {
    LC_ALL=C _utf8_walk "$1" -1
}

# Truncate to at most $2 display cells, appending an ellipsis when cut.
truncate_display() {
    local s="$1" max="$2" w
    w=$(str_display_width "$s")
    if ((w <= max)); then
        printf '%s\n' "$s"
        return 0
    fi
    LC_ALL=C _utf8_walk "$s" "$max"
}

# --- Unread tracking -------------------------------------------------------
# seen/<tower_id> stores the activity epoch last shown to the user (i.e. the
# session was selected in the Navigator, whose view pane displays it live).
# A session whose transcript moved past that epoch has output the user has
# not looked at yet -> unread mark once it stops working.
TOWER_SEEN_DIR="${CLAUDE_TOWER_SEEN_DIR:-${TOWER_NAV_STATE_DIR:-/tmp/claude-tower}/seen}"

# Record the session's current activity as seen.
mark_session_seen() {
    local session_id="$1"
    local jsonl
    jsonl=$(find_session_jsonl "${session_id#tower_}") || return 0
    mkdir -p "$TOWER_SEEN_DIR" 2>/dev/null || return 0
    get_session_activity "$jsonl" >"${TOWER_SEEN_DIR}/${session_id}" 2>/dev/null || true
}

# Baseline a session the Navigator sees for the first time. Without this a
# never-selected session has no seen mark, so its busy->stop transition
# could not be detected as unread. No-op if a mark already exists.
init_session_seen() {
    local session_id="$1"
    [[ -f "${TOWER_SEEN_DIR}/${session_id}" ]] && return 0
    mark_session_seen "$session_id"
}

# 0 (unread) when activity moved past the seen mark. Busy sessions are the
# caller's business - it shows a spinner instead of the unread mark.
is_session_unread() {
    local session_id="$1"
    local seen_file="${TOWER_SEEN_DIR}/${session_id}"
    [[ -f "$seen_file" ]] || return 1
    local jsonl activity seen
    jsonl=$(find_session_jsonl "${session_id#tower_}") || return 1
    activity=$(get_session_activity "$jsonl")
    seen=$(cat "$seen_file" 2>/dev/null) || return 1
    [[ "$seen" =~ ^[0-9]+$ ]] || return 1
    ((activity > seen))
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
