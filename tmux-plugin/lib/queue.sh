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
    label=$(queue_label "$session_id")
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
