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

# Include guard — see common.sh for why this matters.
[[ -n "${_TOWER_CLAUDE_SESSIONS_LOADED:-}" ]] && return 0
_TOWER_CLAUDE_SESSIONS_LOADED=1

CLAUDE_PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
CLAUDE_HISTORY_FILE="${CLAUDE_HISTORY_FILE:-$HOME/.claude/history.jsonl}"
CLAUDE_LIVE_SESSIONS_DIR="${CLAUDE_LIVE_SESSIONS_DIR:-$HOME/.claude/sessions}"
TOWER_BUSY_WINDOW="${TOWER_BUSY_WINDOW:-45}"

# Slugify a cwd the way Claude Code names its project dirs: every "/" (and
# other non-alnum run) becomes "-", so "/home/dev/working/foo" becomes
# "-home-dev-working-foo". Used to tell a session's canonical transcript
# (the one under the slug matching its own launch cwd) from stray copies.
_cwd_to_slug() {
    local cwd="$1"
    # Claude replaces every non-alphanumeric character with a single dash.
    # Done with bash's own substitution rather than sed: this sits on the
    # list-rebuild path, where every external command is a fork+exec.
    local slug="${cwd//[^a-zA-Z0-9]/-}"
    printf '%s\n' "$slug"
}


# Find the transcript for a Claude session ID (without tower_ prefix).
# Output: absolute path. Returns 1 if not found.
#
# The same sessionId can have a transcript under MORE THAN ONE slug dir
# (a session that cd'd between projects, or worktree/scratchpad slugs whose
# path doesn't match the recorded cwd). A plain glob returns whichever the
# shell expands first — arbitrary sort order, not the real launch dir — so
# the list would group the session under the wrong directory header.
#
# Resolve deterministically toward the CANONICAL transcript:
#   1. the candidate whose slug basename equals its own recorded launch cwd
#      slugified (i.e. the transcript that actually belongs to that dir);
#   2. failing that, the newest one by mtime (the session's latest home).
# A single candidate is returned as-is without any extra stat/grep cost.
find_session_jsonl() {
    local session_id="$1"
    local f
    local -a candidates=()
    for f in "$CLAUDE_PROJECTS_DIR"/*/"${session_id}".jsonl; do
        [[ -f "$f" ]] || continue
        candidates+=("$f")
    done

    case ${#candidates[@]} in
        0) return 1 ;;
        1) echo "${candidates[0]}"; return 0 ;;
    esac

    # Multiple slugs hold this sessionId. Prefer the one whose slug matches
    # the transcript's own launch cwd.
    local slug cwd
    for f in "${candidates[@]}"; do
        slug="${f%/*}"
        slug="${slug##*/}"
        cwd=$(get_session_cwd "$f" 2>/dev/null) || continue
        [[ -z "$cwd" ]] && continue
        if [[ "$slug" == "$(_cwd_to_slug "$cwd")" ]]; then
            echo "$f"
            return 0
        fi
    done

    # No slug matched its own cwd — fall back to the newest transcript.
    local newest="" newest_mtime=-1 mtime
    for f in "${candidates[@]}"; do
        mtime=$(stat -c %Y -- "$f" 2>/dev/null) || continue
        if ((mtime > newest_mtime)); then
            newest_mtime=$mtime
            newest="$f"
        fi
    done
    [[ -n "$newest" ]] && { echo "$newest"; return 0; }

    # stat failed for all; return the first candidate so callers still work.
    echo "${candidates[0]}"
    return 0
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
    local latest=0 f
    local -a batch=("$jsonl")

    # Path arithmetic with bash's own operators. dirname/basename here cost
    # three forks per session, and this runs for every row of every rebuild.
    local dir="${jsonl%/*}"
    local base="${jsonl##*/}"
    local session_id="${base%.jsonl}"
    local slug="${dir##*/}"

    for f in "${dir}/${session_id}/subagents"/*.jsonl; do
        [[ -f "$f" ]] && batch+=("$f")
    done

    for f in "${TMPDIR:-/tmp}/claude-${EUID}/${slug}/${session_id}/tasks"/*.output; do
        [[ -f "$f" ]] && batch+=("$f")
    done

    # One stat for the whole batch instead of one per file. A busy session can
    # own dozens of subagent and task files, and statting them individually was
    # the single largest source of processes in a rebuild (measured: 1,131 of
    # 1,614 execve calls across 19 sessions).
    local t
    while IFS= read -r t; do
        [[ "$t" =~ ^[0-9]+$ ]] || continue
        ((t > latest)) && latest=$t
    done < <(stat -c %Y -- "${batch[@]}" 2>/dev/null)

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
        session_id="${f##*/}"
        session_id="${session_id%.jsonl}"
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

# The session id a pid is really running.
#
# The .json records the id claude launched with, which goes stale the moment
# the process resumes a different session: `claude --resume <id>` keeps
# writing the ORIGINAL sessionId while actually running <id>. argv is the
# only place the truth survives, so it wins when it disagrees. Falls back to
# the recorded id when argv is unreadable (a foreign-owned /proc entry) or
# carries no --resume.
_live_session_id() {
    local pid="$1" recorded="$2" argv rid
    argv=$(tr '\0' '\n' < "/proc/${pid}/cmdline" 2>/dev/null) || { echo "$recorded"; return 0; }
    rid=$(grep -A1 -x -F -- '--resume' <<<"$argv" | tail -1)
    if [[ "$rid" =~ ^[0-9a-fA-F-]{36}$ ]]; then
        echo "$rid"
    else
        echo "$recorded"
    fi
}

# Live claude processes, from Claude's own per-process files
# (~/.claude/sessions/<pid>.json, written by every running claude).
# Output: <sessionId>\t<pid>\t<cwd>   one line per process that is alive.
#
# Only real sessions are listed. `"kind":"bg"` covers the daemon helpers
# (`claude bg-spare`, bg-pty-host) — they carry a sessionId and cwd like any
# session, but they are infrastructure: nothing a user can attach to or would
# recognise as work in their project.
list_live_claude_processes() {
    local f pid line sid cwd kind
    for f in "$CLAUDE_LIVE_SESSIONS_DIR"/*.json; do
        [[ -f "$f" ]] || continue
        pid="${f##*/}"
        pid="${pid%.json}"
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        kill -0 "$pid" 2>/dev/null || continue
        line=$(head -c 2000 -- "$f" 2>/dev/null) || continue
        kind=$(grep -o '"kind":"[^"]*"' <<<"$line") || kind=""
        kind="${kind#\"kind\":\"}"
        kind="${kind%\"}"
        [[ "$kind" == "bg" ]] && continue
        sid=$(grep -o '"sessionId":"[^"]*"' <<<"$line") || continue
        sid="${sid#\"sessionId\":\"}"
        sid="${sid%\"}"
        sid=$(_live_session_id "$pid" "$sid")
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

# --- Wait-queue detection --------------------------------------------------
# A session is "waiting" when Claude has stopped and needs the user. The
# status field in ~/.claude/sessions/<pid>.json cannot tell a permission
# prompt from a finished session (both read "idle") — the distinguishing
# signal is on screen, so managed sessions are classified by their pane.

# Last lines of a Tower-managed session's pane. Isolated so tests can stub
# it (capture-pane needs a live tmux server). Empty when uncapturable.
capture_pane_signature() {
    local session_id="$1"
    session_tmux capture-pane -t "$session_id" -p 2>/dev/null | grep -v '^$' | tail -n 8 || true
}

# Classify a chunk of pane text into a wait kind, or empty if the pane
# shows work in progress. Signatures verified against live Claude panes.
#   working (esc to interrupt)      -> "" (not waiting)
#   [y/N] / "Do you want" + Yes/No  -> permission
#   "❯ 1." numbered menu            -> question
#   otherwise                       -> input (finished, awaiting a prompt)
classify_pane_wait() {
    local text="$1"
    if printf '%s' "$text" | grep -qiE 'esc to interrupt|to interrupt\)'; then
        echo ""
        return 0
    fi
    if printf '%s' "$text" | grep -qiE '\[y/n\]|do you want|yes, and|no, and (tell|keep)|proceed\?'; then
        echo "permission"
        return 0
    fi
    if printf '%s' "$text" | grep -qE '❯ ?[0-9]\.'; then
        echo "question"
        return 0
    fi
    echo "input"
}

# Wait kind for a session, or empty when it is not waiting on the user.
#   busy / working              -> "" (skip)
#   managed + idle              -> classify by pane
#   external (live, no pane)    -> coarse "input" (can't see the prompt)
#   dead/lost (registered)      -> error
#   dormant                     -> "" (not waiting)
# $2 (optional): pre-fetched pane text, so a caller that already captured
# the pane (or a test) can pass it instead of shelling out again.
get_wait_state() {
    local session_id="$1"
    local pane="${2-}"
    local claude_id="${session_id#tower_}"
    local jsonl

    if session_tmux has-session -t "$session_id" 2>/dev/null; then
        # Managed: a real pane exists. Working sessions are not waiting.
        if jsonl=$(find_session_jsonl "$claude_id") && is_session_busy "$jsonl"; then
            echo ""
            return 0
        fi
        [[ -z "${2+set}" ]] && pane=$(capture_pane_signature "$session_id")
        classify_pane_wait "$pane"
        return 0
    fi

    has_metadata "$session_id" || { echo ""; return 0; }

    if ! jsonl=$(find_session_jsonl "$claude_id"); then
        echo "error"   # lost: transcript gone
        return 0
    fi
    local cwd
    cwd=$(get_session_cwd "$jsonl" || true)
    if [[ -z "$cwd" || ! -d "$cwd" ]]; then
        echo "error"   # dead: cwd gone
        return 0
    fi
    if is_claude_process_alive "$claude_id"; then
        echo "input"   # external live process — coarse, pane unreachable
        return 0
    fi
    echo ""            # dormant: registered, not running, not waiting
}

# Epoch when the wait began ≈ when work last stopped (newest activity).
# Returns 0 when unknown, so an unknown wait sorts as oldest (surfaced).
wait_since() {
    local session_id="$1"
    local claude_id="${session_id#tower_}"
    local jsonl
    jsonl=$(find_session_jsonl "$claude_id" 2>/dev/null) || { echo 0; return 0; }
    get_session_activity "$jsonl"
}

# Count of live claude processes in a directory whose session is NOT
# registered in Tower — forks/sessions started outside Tower's tmux.
#
# $2 (optional): a pre-fetched live-process table (the output of
# list_live_claude_processes). Scanning the live-process table means walking
# ~/.claude/sessions, one kill -0 + grep per entry — a full rescan per call.
# build_session_list calls this once per project dir, so without the snapshot
# it rescans the same table N times per refresh. Pass the table in to scan the
# processes once and reuse it. Falls back to a fresh scan when omitted.
count_unregistered_processes_in_dir() {
    local dir="$1"
    local table="${2-}"
    local sid _pid cwd n=0
    local -a counted=()
    local seen s
    # Identity of the session hosting Tower. claude exports both; the pid is
    # the unambiguous key (a session id can span several pids), the id is the
    # fallback when the navigator runs one process removed from claude.
    local self_pid="${CLAUDE_PID:-}" self_sid="${CLAUDE_CODE_SESSION_ID:-}"
    if [[ -z "${2+set}" ]]; then
        table=$(list_live_claude_processes)
    fi
    while IFS=$'\t' read -r sid _pid cwd; do
        [[ -z "$sid" ]] && continue
        [[ "$cwd" == "$dir" ]] || continue
        has_metadata "tower_${sid}" && continue
        # The session hosting Tower itself is not an unnoticed stray — it is
        # the user, right here. Counting it would put a ⚡ on every project
        # dir the user actually works in, which is where the mark is least
        # informative and most alarming.
        [[ -n "$self_pid" && "$_pid" == "$self_pid" ]] && continue
        [[ -n "$self_sid" && "$sid" == "$self_sid" ]] && continue
        # One session can hold several live pids, in several dirs (a resumed
        # session leaves its old process running). The mark counts SESSIONS
        # you cannot see, so each id contributes at most one.
        seen=0
        for s in "${counted[@]:-}"; do
            [[ "$s" == "$sid" ]] && seen=1 && break
        done
        ((seen)) && continue
        counted+=("$sid")
        n=$((n + 1))
    done <<<"$table"
    echo "$n"
}

# Count of a session's subagents active within TOWER_BUSY_WINDOW.
count_active_subagents() {
    local jsonl="$1"
    local dir session_id now t f n=0
    dir="${jsonl%/*}"
    session_id="${jsonl##*/}"
    session_id="${session_id%.jsonl}"
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

# A slash command reaches the transcript already expanded by Claude, as
#   <command-message>name</command-message><command-name>/name</command-name>
#   <command-args>the user's actual words</command-args>
# Only the args carry meaning; the rest is machinery. Unwrap to the args
# when present, otherwise drop the tags and keep whatever text remains.
_strip_command_markup() {
    local s="$1"
    # Boilerplate Claude prepends to prompts typed during a local command.
    # It precedes the real text, so drop the element and keep what follows.
    if [[ "$s" == *"<local-command-caveat>"* ]]; then
        if [[ "$s" == *"</local-command-caveat>"* ]]; then
            s="${s%%<local-command-caveat>*}${s#*</local-command-caveat>}"
        else
            s="${s%%<local-command-caveat>*}"
        fi
    fi
    if [[ "$s" == *"<command-args>"* ]]; then
        s="${s#*<command-args>}"
        s="${s%%</command-args>*}"
    elif [[ "$s" == *"<command-"* ]]; then
        # A bare command with no args. command-message/command-name wrap the
        # command's own identity, not the user's words, so drop each element
        # whole — keeping their text would title the row "init/init".
        local out="" head
        while [[ "$s" == *"<command-"* ]]; do
            head="${s%%<command-*}"
            out+="$head"
            s="${s#*<command-}"
            # Past this element's closing tag, if it has one.
            if [[ "$s" == *"</command-"* ]]; then
                s="${s#*</command-}"
                s="${s#*>}"
            else
                s="${s#*>}"
            fi
        done
        s="${out}${s}"
    fi
    while [[ "$s" == " "* ]]; do s="${s# }"; done
    while [[ "$s" == *" " ]]; do s="${s% }"; done
    printf '%s\n' "$s"
}

# Last-resort title for a session whose every prompt is a slash command:
# the command's argument ("/brainstorming make X nicer" -> "make X nicer").
# Preferred over falling through to the transcript, whose first message for
# such a session is the raw command expansion. Returns 1 when the command
# carries no argument (bare "/init" says nothing about the work).
_slash_command_argument() {
    local s="$1"
    s="${s//\\n/ }"
    s="${s//\\t/ }"
    s="${s//$'\t'/ }"
    s="${s//\\\"/\"}"
    s=$(_strip_command_markup "$s")
    while [[ "$s" == " "* ]]; do s="${s# }"; done
    [[ "$s" == /* ]] || return 1
    # Drop the command word; what follows is the user's own text.
    [[ "$s" == *" "* ]] || return 1
    s="${s#* }"
    _first_meaningful_sentence "$s"
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
    # Titles come from whatever the user typed at Claude, and rows are drawn
    # with printf into a width-budgeted frame. An escape sequence in that text
    # would repaint the list — colour bleeding into later rows, the cursor
    # moving — and str_display_width counts its bytes as visible cells, so the
    # row overflows too. Strip CSI runs, then any stray control byte.
    while [[ "$s" == *$'\033['* ]]; do
        local head="${s%%$'\033['*}" rest="${s#*$'\033['}"
        while [[ -n "$rest" && "$rest" != [a-zA-Z]* ]]; do rest="${rest:1}"; done
        s="${head}${rest:1}"
    done
    s="${s//[$'\001'-$'\037']/}"
    s="${s//$'\177'/}"
    s=$(_strip_command_markup "$s")
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
    local line title raw
    local -a displays=()
    if [[ -f "$CLAUDE_HISTORY_FILE" ]]; then
        # First few prompts of this session, oldest first. The very first
        # one is often a bare slash command or a one-word nudge that says
        # nothing about the work — walk forward until something does.
        while IFS= read -r line; do
            # Pull "display":"..." out with bash's own matching. This used to
            # be `printf | grep -o`, i.e. two more processes for every history
            # line examined, on a path the list rebuild walks once per session.
            [[ "$line" == *'"display":"'* ]] || continue
            raw="${line#*\"display\":\"}"
            raw="${raw%%\"*}"
            displays+=("$raw")
            title=$(_first_meaningful_sentence "$raw") || continue
            printf '%s\n' "$title"
            return 0
        done < <(grep -m 5 -F "\"sessionId\":\"${session_id}\"" -- "$CLAUDE_HISTORY_FILE" 2>/dev/null)

        # Every prompt was a slash command. Its argument is still a better
        # title than the transcript, which for these sessions holds only
        # Claude's raw command expansion.
        for raw in "${displays[@]}"; do
            title=$(_slash_command_argument "$raw") || continue
            printf '%s\n' "$title"
            return 0
        done
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
    # The raw-title fallback must never emit command expansion markup.
    _first_meaningful_sentence "$title" && return 0
    _slash_command_argument "$title" && return 0
    # Stripping can leave nothing at all — a message that was pure markup,
    # e.g. "<command-message>init</command-message><command-name>/init</…>".
    # Succeeding with an empty line would render a blank row: callers only
    # fall back to the id prefix on a non-zero exit, not on empty output.
    local stripped
    stripped=$(_strip_command_markup "$title")
    [[ -n "$stripped" ]] || return 1
    printf '%s\n' "$stripped"
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
    # _utf8_walk treats a negative max as "measure, don't cut" and returns the
    # width as a number. Callers here always mean "cut": navigator-list.sh
    # computes budget - name_w - 3, which goes negative on a long session name
    # in a narrow pane, and would then have printed the digit count as the row
    # label. Clamp instead.
    ((max < 0)) && max=0
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
