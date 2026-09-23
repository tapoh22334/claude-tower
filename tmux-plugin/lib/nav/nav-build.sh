#!/usr/bin/env bash
# shellcheck shell=bash
# nav-build.sh - Building the session arrays the rest of the list reads.
#
# Owns SESSION_IDS and its parallel arrays, the per-row label and project
# directory, the group ordering, and the scan that fills them in.

# ============================================================================
# Session List Management
# ============================================================================

# Session arrays
declare -a SESSION_IDS=()
declare -a SESSION_DISPLAYS=()
# Project dir per row ("" for broken rows) and the group-header text to
# print before a row ("" = row continues the previous group).
declare -a SESSION_DIRS=()
declare -a SESSION_HEADERS=()
# Index into SESSION_IDS where broken (dead/lost) sessions start; -1 = none
BROKEN_START=-1

# Row label inside a project group: the group header already names the
# directory, so the row shows the conversation title (what distinguishes
# sessions sharing a project), plus " (name)" when the registry has one.
_session_label() {
    local session_id="$1"
    local claude_id label="" name=""
    claude_id=$(live_claude_id "$session_id")

    # A registry name is the user's own words for this session — when one
    # exists it IS the label, no title needed.
    if load_metadata "$session_id" 2>/dev/null && [[ -n "$META_SESSION_NAME" ]]; then
        name="$META_SESSION_NAME"
    fi
    label=$(get_session_title "$claude_id" 2>/dev/null) || label=""
    [[ -z "$label" ]] && label="${claude_id:0:7}"

    # Budget: content width minus the indent (2), state icon (2) and the
    # fixed right status column. Cut by display cells — a Japanese title
    # counted in characters overflows the row and wraps onto a second line.
    local width budget
    width=$(_content_width)
    budget=$((width - 4 - NAV_RIGHT_COL))
    ((budget < 20)) && budget=20

    if [[ -n "$name" ]]; then
        # "name — title", with the name never sacrificed to the title.
        local name_w
        name_w=$(str_display_width "$name")
        if ((name_w + 6 >= budget)); then
            truncate_display "$name" "$budget"
            return 0
        fi
        printf '%s — %s\n' "$name" "$(truncate_display "$label" $((budget - name_w - 3)))"
        return 0
    fi
    truncate_display "$label" "$budget"
}

# Project dir of a session ("" when unknown).
#
# The transcript is the authority — it is where the session actually is, and
# it keeps up if the session outlives the directory it was launched from. But
# it does not exist for the first seconds of a new session, and a row with no
# directory lands in the unknown group at the bottom of the list only to jump
# to its real project once the transcript appears. So fall back to the launch
# dir recorded at registration, and only for as long as the transcript has
# nothing to say.
_session_dir() {
    local session_id="$1" jsonl cwd="" claude_id
    claude_id=$(live_claude_id "$session_id")
    # `local` on the META_* names: load_metadata assigns them unconditionally,
    # and this runs mid-loop in build_session_list, so leaking them would let
    # one row's directory lookup overwrite another row's loaded name.
    local META_SESSION_NAME="" META_CREATED_AT="" META_LAUNCH_DIR=""
    if jsonl=$(find_session_jsonl "$claude_id" 2>/dev/null); then
        cwd=$(get_session_cwd "$jsonl" 2>/dev/null) || cwd=""
    fi
    if [[ -z "$cwd" ]] && load_metadata "$session_id" 2>/dev/null; then
        cwd="$META_LAUNCH_DIR"
    fi
    echo "$cwd"
}

# Build session list: normal states first, broken (dead/lost) last.
# Sort key for a project group: "1\t" for the unknown (empty) dir so it sinks
# to the bottom whatever it is called, else "0<basename>\t<dir>" so groups
# order by project name and two same-named projects stay apart by path.
_group_sort_key() {
    local d="$1" base
    if [[ -z "$d" ]]; then
        printf '1\t\n'
        return 0
    fi
    base="${d%/}"
    base="${base##*/}"
    [[ -z "$base" ]] && base="/"
    printf '0%s\t%s\n' "$base" "$d"
}

# 0 if group dir $1 sorts before group dir $2 (same collation as the rebuild).
_group_sorts_before() {
    local a b first
    a=$(_group_sort_key "$1")
    b=$(_group_sort_key "$2")
    [[ "$a" == "$b" ]] && return 1
    first=$(printf '%s\n%s\n' "$a" "$b" | LC_ALL=C sort -f | head -n 1)
    [[ "$first" == "$a" ]]
}

build_session_list() {
    SESSION_IDS=()
    SESSION_DISPLAYS=()
    SESSION_DIRS=()
    SESSION_HEADERS=()
    BROKEN_START=-1

    local -a raw_ids=() raw_displays=() raw_dirs=()
    local -a broken_ids=() broken_displays=()
    local session_id state label selected dir jsonl agents badge

    # Re-read the terminal width once for this pass.
    _reset_width_cache

    # Snapshot the live-process table ONCE for this whole build. The per-dir
    # unmanaged-process count would otherwise rescan ~/.claude/sessions (a
    # kill -0 + grep per entry) once for every project group; one snapshot,
    # reused, replaces N full rescans per refresh.
    local live_procs
    live_procs=$(list_live_claude_processes)
    # Resolve which session each pane is really running, once for this
    # build (see live_claude_id). Bare call: it writes globals.
    build_live_id_map

    # The selected session is on screen in the view pane: whatever it has
    # produced counts as seen. Everything else gets a baseline mark so a
    # later busy->stop transition can be flagged as unread.
    selected=$(get_nav_selected)

    local icon marks
    while IFS=: read -r session_id state; do
        [[ -z "$session_id" ]] && continue
        if [[ "$session_id" == "$selected" ]]; then
            mark_session_seen "$session_id"
        else
            init_session_seen "$session_id"
        fi

        # Unread is a STATE, not a right-column mark: a stopped session that
        # produced output since it was last viewed becomes newmsg, shown by
        # the ✱ left icon like any other state. The right column is left to
        # the subagent count alone.
        #
        # busy and starting are deliberately not on this list. Neither can
        # have unread output to report: busy is still producing it, and
        # starting has no transcript to have produced any. starting also
        # expires on its own, so it cannot strand a row that never updates.
        if [[ "$state" == "active" || "$state" == "dormant" || "$state" == "external" ]] &&
            is_session_unread "$session_id"; then
            state="newmsg"
        fi
        badge=""
        if [[ "$state" == "busy" ]] &&
            jsonl=$(find_session_jsonl "$(live_claude_id "$session_id")" 2>/dev/null); then
            agents=$(count_active_subagents "$jsonl")
            if [[ "$agents" -gt 0 ]]; then
                badge="${NAV_C_DIM}⚙${agents}${NAV_C_NORMAL}"
            fi
        fi
        marks="$badge"

        label=$(_session_label "$session_id")
        dir=$(_session_dir "$session_id")
        case "$state" in
            busy)    icon="${NAV_C_ACCENT}${SPIN_PLACEHOLDER}${NAV_C_NORMAL}" ;;
            starting)
                # Claude is launching and has written nothing yet, so there is
                # no title to show. Say so rather than showing a bare short id
                # that looks like an ordinary row.
                icon="${NAV_C_DIM}${ICON_STATE_STARTING}${NAV_C_NORMAL}"
                label="${NAV_C_DIM}${label} — starting…${NAV_C_NORMAL}"
                ;;
            newmsg)  icon="${NAV_C_ACCENT}✱${NAV_C_NORMAL}" ;;
            active)  icon="${NAV_C_ACTIVE}▶${NAV_C_NORMAL}" ;;
            external) icon="${NAV_C_EXTERNAL}◇${NAV_C_NORMAL}" ;;
            dormant) icon="${NAV_C_DORMANT}○${NAV_C_NORMAL}" ;;
            dead)
                broken_ids+=("$session_id")
                broken_displays+=("$(_compose_row "${NAV_C_ERROR}✗${NAV_C_NORMAL}" "$label" "")")
                continue
                ;;
            lost)
                broken_ids+=("$session_id")
                broken_displays+=("$(_compose_row "${NAV_C_ERROR}?${NAV_C_NORMAL}" "$label" "")")
                continue
                ;;
            *) continue ;;
        esac
        raw_ids+=("$session_id")
        raw_dirs+=("$dir")
        raw_displays+=("$(_compose_row "$icon" "$label" "$marks")")
    done < <(list_all_sessions)

    # Regroup by project dir: groups sorted by project name so the order is
    # stable across refreshes, with the unknown-dir group pinned last; rows
    # within a group by id. Headers are precomputed here so spinner ticks can
    # re-render without touching the process table.
    local -a dirs_seen=()
    local d seen_d found i j header extern
    for ((i = 0; i < ${#raw_ids[@]}; i++)); do
        d="${raw_dirs[$i]}"
        found=0
        for seen_d in "${dirs_seen[@]:-}"; do
            if [[ "$seen_d" == "$d" ]]; then found=1; fi
        done
        if [[ $found -eq 1 ]]; then continue; fi
        dirs_seen+=("$d")
    done

    # Groups are ordered by _group_sort_key: unknown last, then project name,
    # ties broken by the full path so two same-named projects stay apart.
    if [[ ${#dirs_seen[@]} -gt 0 ]]; then
        local -a sort_keys=()
        for seen_d in "${dirs_seen[@]}"; do
            sort_keys+=("$(_group_sort_key "$seen_d")")
        done
        mapfile -t dirs_seen < <(printf '%s\n' "${sort_keys[@]}" | LC_ALL=C sort -f | cut -f2-)
    fi

    for ((i = 0; i < ${#dirs_seen[@]}; i++)); do
        d="${dirs_seen[$i]}"

        extern=$(count_unregistered_processes_in_dir "$d" "$live_procs")
        header=$(_compose_group_header "$d" "$extern")

        # Rows inside a group are ordered by id (strcmp). list_all_sessions
        # hands us live tmux rows in tmux's name order followed by the
        # dormant .meta-only rows, i.e. two blocks; a row seated optimistically
        # by _remember_session_row cannot know which block a neighbour is in,
        # so the one order both sides can compute is plain id order. That is
        # what keeps a freshly made row from moving when this rebuild lands.
        local -a members=()
        for ((j = 0; j < ${#raw_ids[@]}; j++)); do
            [[ "${raw_dirs[$j]}" == "$d" ]] && members+=("${raw_ids[$j]}"$'\t'"$j")
        done
        while IFS=$'\t' read -r _ j; do
            [[ -n "$j" ]] || continue
            SESSION_IDS+=("${raw_ids[$j]}")
            SESSION_DISPLAYS+=("${raw_displays[$j]}")
            SESSION_DIRS+=("$d")
            SESSION_HEADERS+=("$header")
            header=""
        done < <(printf '%s\n' "${members[@]}" | LC_ALL=C sort -t $'\t' -k1,1)
    done

    if [[ ${#broken_ids[@]} -gt 0 ]]; then
        BROKEN_START=${#SESSION_IDS[@]}
        local k
        for ((k = 0; k < ${#broken_ids[@]}; k++)); do
            SESSION_IDS+=("${broken_ids[$k]}")
            SESSION_DISPLAYS+=("${broken_displays[$k]}")
            SESSION_DIRS+=("")
            SESSION_HEADERS+=("")
        done
    fi
}

# Get current selection index from state
get_selection_index() {
    local selected
    selected=$(get_nav_selected)

    if [[ -z "$selected" ]]; then
        echo 0
        return
    fi

    local i=0
    for id in "${SESSION_IDS[@]:-}"; do
        if [[ "$id" == "$selected" ]]; then
            echo "$i"
            return
        fi
        ((i++)) || true
    done

    # Not found, return 0
    echo 0
}
