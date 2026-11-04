#!/usr/bin/env bash
# shellcheck shell=bash
# queue.sh - Which sessions are waiting on the user, newest wait first, and
# what they last said.
#
# Shared by queue-view.sh (the queue itself) and tail-view.sh (which follows
# the top of the queue). Source it after common.sh.

# Wait kind -> icon and color. The color tells the kinds apart at a glance;
# the glyph keeps them apart where color is not available.
_wait_icon() {
    case "$1" in
        permission) echo "⚠" ;;
        question) echo "？" ;;
        input) echo "✱" ;;
        error) echo "✗" ;;
        *) echo "·" ;;
    esac
}

# Foreground only, so the row's reverse-video highlight survives it: callers
# close it with \033[39m, never with a full reset.
_wait_color() {
    case "$1" in
        permission) printf '\033[33m' ;; # yellow: Claude is blocked on a yes/no
        question) printf '\033[36m' ;;   # cyan: Claude asked something
        input) printf '\033[32m' ;;      # green: turn finished, your move
        error) printf '\033[31m' ;;      # red: dead or lost
        *) printf '\033[39m' ;;
    esac
}

# Row label: the conversation title, or the short id when there is none.
queue_label() {
    local claude_id="${1#tower_}" title
    title=$(get_session_title "$claude_id" 2>/dev/null) || title=""
    title="${title//\\n/ }"
    title="${title//\\t/ }"
    title="${title//$'\t'/ }"
    [[ -z "$title" ]] && title="${claude_id:0:7}"
    printf '%s\n' "$title"
}

# Project name: the basename of the directory the session runs in. "-" when
# unknown, never empty — the entry line is tab-separated and read with
# IFS=$'\t', which collapses an empty field into its neighbour.
queue_project() {
    local session_id="$1" jsonl cwd=""
    if jsonl=$(find_session_jsonl "$(live_claude_id "$session_id")" 2>/dev/null); then
        cwd=$(get_session_cwd "$jsonl" 2>/dev/null) || cwd=""
    fi
    if [[ -z "$cwd" ]]; then
        local META_SESSION_NAME="" META_CREATED_AT="" META_LAUNCH_DIR="" META_LIVE_ID=""
        load_metadata "$session_id" 2>/dev/null && cwd="$META_LAUNCH_DIR"
    fi
    cwd="${cwd%/}"
    cwd="${cwd##*/}"
    printf '%s\n' "${cwd:--}"
}

# What a blocked session waits on, from its transcript: the question it
# asked, or the tool it wants to run and on what. Returns 1 when there is
# no transcript or nothing pending in it.
queue_pending() {
    local jsonl
    jsonl=$(find_session_jsonl "$(live_claude_id "$1")" 2>/dev/null) || return 1
    pending_request "$jsonl"
}

# One session's line: "<since>\t<id>\t<kind>\t<project>\t<label>".
# kind is "-" when the session is not waiting; such sessions are left out
# unless $2 is "all".
_queue_entry() {
    local session_id="$1" all="${2-}" kind since project label
    kind=$(get_wait_state "$session_id")
    if [[ -z "$kind" ]]; then
        [[ "$all" == all ]] || return 0
        kind="-"
    fi
    since=$(wait_since "$session_id")
    project=$(queue_project "$session_id")
    # A blocked session is labelled with what it is blocked on: that, not the
    # conversation's opening line, is what you answer (#111). A session
    # waiting for a prompt has nothing pending, so it keeps its title.
    label=""
    case "$kind" in
        permission | question) label=$(queue_pending "$session_id") || label="" ;;
    esac
    [[ -n "$label" ]] || label=$(queue_label "$session_id")
    printf '%s\t%s\t%s\t%s\t%s\n' "$since" "$session_id" "$kind" "$project" "$label"
}

# Waiting sessions, the most recent wait first: the session that just
# stopped is the one whose context is still in your head, so it leads.
# With "all", the sessions that are not waiting follow, most recently
# active first.
#
# Each session is checked in its own background job. The checks are
# independent and each spends its time waiting on tmux and the filesystem
# (~25-60ms apiece); one after another they made opening the queue take
# about a second with two dozen sessions (#86). Lines are far below
# PIPE_BUF, so concurrent writers cannot interleave inside one.
#
# Run it under $(...) or < <(...): the process snapshot it takes is meant to
# die with the subshell, not to go stale in the caller.
collect_queue() {
    local all="${1-}" ids live session_id
    ids=$(list_all_session_ids)
    live=$'\n'$(session_tmux list-sessions -F '#{session_name}' 2>/dev/null || true)$'\n'

    # A paneless session asks is_claude_process_alive, and each rescan of the
    # process table costs ~0.5s. Take it once, and only when it will be read.
    while IFS= read -r session_id; do
        [[ -z "$session_id" || "$live" == *$'\n'"$session_id"$'\n'* ]] && continue
        LIVE_PROCS_TABLE=$(list_live_claude_processes)
        LIVE_PROCS_READY=1
        break
    done <<<"$ids"

    {
        while IFS= read -r session_id; do
            [[ -z "$session_id" ]] && continue
            _queue_entry "$session_id" "$all" &
        done <<<"$ids"
        wait
    } | sort -t "$(printf '\t')" -k1,1nr -k2,2 |
        awk -F '\t' '$3 != "-" { print; next } { rest = rest $0 ORS } END { printf "%s", rest }'
}

# The end of a session's conversation, as display lines: user prompts
# prefixed with "❯ ", Claude's replies as written, a blank line between
# messages, every line wrapped to $3 cells. Tool calls and their results are
# left out — they are what fills the pane, and the point here is what was
# said. Prints the last $2 lines; returns 1 when there is nothing to show
# (no jq, no transcript, no message yet) so the caller can fall back to the
# pane.
#
# Reads only the transcript's last TOWER_TAIL_BYTES: transcripts grow to
# tens of MB, and the tail is all that is shown. The cut can land mid-line,
# so lines that do not parse are skipped rather than failing the read.
TOWER_TAIL_BYTES="${TOWER_TAIL_BYTES:-400000}"
# Only the last few messages are wrapped: wrapping walks every character in
# jq, and doing it for the whole tail cost ~250ms per session where parsing
# alone costs ~30ms. A block shows a dozen lines at most.
TOWER_TAIL_MESSAGES="${TOWER_TAIL_MESSAGES:-6}"
# shellcheck disable=SC2016  # jq program: $m, $w are jq variables
# cw counts a cell as wide when it may be: the symbol blocks (⏳ ✅ ⭐ …) mix
# wide and narrow glyphs, and counting a narrow one as wide only wraps a
# line early, while the reverse makes it wrap on screen and scroll the frame.
readonly _TRANSCRIPT_TAIL_JQ='
def cw: if (. >= 4352 and . <= 4447) or (. >= 11904 and . <= 42191)
        or (. >= 8960 and . <= 9215) or (. >= 9728 and . <= 10175)
        or (. >= 11008 and . <= 11263) or (. >= 126976 and . <= 127743)
        or (. >= 44032 and . <= 55203) or (. >= 63744 and . <= 64255)
        or (. >= 65072 and . <= 65103) or (. >= 65280 and . <= 65376)
        or (. >= 65504 and . <= 65510) or (. >= 127744 and . <= 129791)
        or (. >= 131072 and . <= 262141)
    then 2 else 1 end;
def wrap($n):
    if . == "" then ""
    else explode
        | reduce .[] as $c ({out: [], cur: [], w: 0};
            ($c | cw) as $k
            | if .w + $k > $n and (.cur | length) > 0
              then .out += [.cur | implode] | .cur = [$c] | .w = $k
              else .cur += [$c] | .w += $k end)
        | (.out + [.cur | implode])[]
    end;
[inputs
    | (try fromjson catch null) as $m
    | select($m | type == "object")
    | select($m.type == "user" or $m.type == "assistant")
    | select(($m.isMeta // false) | not)
    | select(($m.isSidechain // false) | not)
    | ($m.message.content
        | if type == "string" then [.]
          elif type == "array" then [.[] | select(.type == "text") | .text]
          else [] end
        | map(select(test("\\S")))) as $texts
    | select($texts | length > 0)
    | ($texts | join("\n")) as $t
    | select($m.type == "assistant" or ($t | startswith("<") | not))
    | if $m.type == "user" then "❯ " + $t else $t end]
| .[-$keep:][]
| ("", (gsub("\t"; "    ") | split("\n")[] | sub("\\s+$"; "") | wrap($w)))
'
transcript_tail() {
    local jsonl="$1" n="$2" width="$3" out
    command -v jq >/dev/null 2>&1 || return 1
    [[ -f "$jsonl" ]] || return 1
    ((width < 10)) && width=10
    out=$(tail -c "$TOWER_TAIL_BYTES" -- "$jsonl" 2>/dev/null |
        jq -nrR --argjson w "$width" --argjson keep "$TOWER_TAIL_MESSAGES" "$_TRANSCRIPT_TAIL_JQ" 2>/dev/null) || return 1
    [[ "$out" == *[![:space:]]* ]] || return 1
    tail -n "$n" <<<"$out"
}

# The first tool call of the current turn that has no result yet: the one
# a permission prompt or a question is holding up. Calls in a turn are
# asked about in order, so with parallel calls the first unanswered one is
# on screen. Only the turn since the last prompt counts: a call from an
# earlier turn that never got its result (a crash) is not what waits now. Prints one line, whitespace collapsed; returns 1 when nothing
# is pending.
#
# The pending call is the transcript's last entry, so a short tail holds
# it. One cut mid-call (a Write of a large file) does not parse and is
# simply not found; the row then keeps its title.
TOWER_PENDING_BYTES="${TOWER_PENDING_BYTES:-100000}"
# shellcheck disable=SC2016  # jq program: $ms, $done, $in are jq variables
readonly _PENDING_REQUEST_JQ='
[inputs | (try fromjson catch null) | select(type == "object")] as $all
| ([$all | to_entries[]
    | select(.value.type == "user" and ((.value.isMeta // false) | not))
    | select(.value.message.content
        | (type == "string") or ([arrays | .[] | select(.type != "tool_result")] | length > 0))
    | .key] | last // -1) as $prompt
| $all[$prompt + 1:] as $ms
| [$ms[] | select(.type == "user") | .message.content | arrays | .[]
    | select(.type == "tool_result") | .tool_use_id] as $done
| first($ms[] | select(.type == "assistant") | .message.content | arrays | .[]
    | select(.type == "tool_use")
    | select(.id as $i | any($done[]; . == $i) | not))
| .name as $n | (.input // {}) as $in
| if $n == "AskUserQuestion" then ($in.questions[0].question // $n)
  else ($in.command // $in.file_path // $in.notebook_path // $in.url
        // $in.query // $in.pattern // $in.skill // $in.description // "")
       | tostring | if . == "" then $n else $n + ": " + . end
  end
| gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "") | .[0:300]
'
pending_request() {
    local jsonl="$1" out
    command -v jq >/dev/null 2>&1 || return 1
    [[ -f "$jsonl" ]] || return 1
    out=$(tail -c "$TOWER_PENDING_BYTES" -- "$jsonl" 2>/dev/null |
        jq -nrR "$_PENDING_REQUEST_JQ" 2>/dev/null) || return 1
    [[ -n "$out" ]] || return 1
    printf '%s\n' "$out"
}

# --- Background reload (#110) ------------------------------------------------
# A reload checks every session (~1s with two dozen). Run in the key loop,
# it held every j/k pressed meanwhile until it ended. The views run it here
# instead and keep reading keys; they apply the result when it is done.
#
# bg_load_start FN runs "FN DIR" in the background, DIR a fresh scratch
# directory for its output. One load at a time: a start while one runs is
# a no-op. bg_load_done returns 0 once it has finished — its output stays
# in BG_LOAD_DIR until bg_load_discard, which also stops a running load
# (the view is closing).
BG_LOAD_PID=""
BG_LOAD_DIR=""

bg_load_start() {
    [[ -n "$BG_LOAD_PID" ]] && return 0
    local lines cols
    # Measured here, handed down: the job runs with no terminal on any of
    # its fds, where tput answers 24x80 whatever the pane is.
    lines=$(_term_lines)
    cols=$(_term_cols)
    BG_LOAD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tower-load.XXXXXX") || return 1
    # The marker, not the pid, says "finished": a child that has exited but
    # not been reaped still answers kill -0. Written whatever FN returns, so
    # a failed load ends the wait instead of stalling every later reload.
    # FN runs in a subshell of its own, so even a fatal shell error in it
    # (an unbound variable under set -u) cannot skip the marker.
    (
        (
            set +e
            export TOWER_TERM_LINES="$lines" TOWER_TERM_COLS="$cols"
            "$@" "$BG_LOAD_DIR"
        ) >/dev/null 2>&1
        : >"$BG_LOAD_DIR/.done"
    ) &
    BG_LOAD_PID=$!
}

bg_load_done() {
    [[ -n "$BG_LOAD_PID" && -f "$BG_LOAD_DIR/.done" ]] || return 1
    wait "$BG_LOAD_PID" 2>/dev/null || true
    BG_LOAD_PID=""
    return 0
}

# Stop $1 and everything under it: the per-session checks run two levels
# down (inside collect_queue's pipeline), out of reach of pkill -P. The tree
# comes from one ps snapshot: this runs when the view closes, and a pgrep
# per process (/proc scanned each time) held up the exit for seconds. All
# are stopped before any is killed, so none forks a child meanwhile.
_kill_tree() {
    local root="$1" pid ppid i
    local -a tree=("$root")
    local -A kids=()
    while read -r pid ppid; do
        kids[$ppid]+=" $pid"
    done < <(ps -e -o pid= -o ppid= 2>/dev/null)
    for ((i = 0; i < ${#tree[@]}; i++)); do
        # shellcheck disable=SC2206  # split the space-separated pid list
        tree+=(${kids[${tree[$i]}]-})
    done
    kill -STOP "${tree[@]}" 2>/dev/null || true
    kill "${tree[@]}" 2>/dev/null || true
    kill -CONT "${tree[@]}" 2>/dev/null || true
}

bg_load_discard() {
    if [[ -n "$BG_LOAD_PID" ]]; then
        _kill_tree "$BG_LOAD_PID"
        wait "$BG_LOAD_PID" 2>/dev/null || true
    fi
    [[ -n "$BG_LOAD_DIR" ]] && rm -rf "$BG_LOAD_DIR"
    BG_LOAD_PID=""
    BG_LOAD_DIR=""
    return 0
}
