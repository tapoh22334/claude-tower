#!/usr/bin/env bash
# shellcheck shell=bash
# nav-optimistic.sh - Showing the result of a change before the rebuild confirms it.
#
# Owns the in-memory edits applied after a delete, add or fork, and the
# settle that publishes them and asks for the confirming rebuild.

# ----------------------------------------------------------------------------
# Optimistic list updates
#
# After a delete or an add, the list has to show the result immediately — the
# user just did the thing and expects to see it. The obvious way to get that
# is to rebuild, which is what these handlers used to do inline: a measured
# 1.4s over 18 sessions, during which `read` never runs, so keystrokes queue
# up and arrive in a burst afterwards. The Navigator looked frozen.
#
# Instead, apply the known outcome to the arrays we already have and redraw
# from those. One row leaves or the cursor moves — cheap, and correct for the
# only thing that changed. The background rebuild then confirms it, so a
# failed operation corrects itself within a tick rather than being asserted
# forever.
# ----------------------------------------------------------------------------

# Drop the row for $1 from the in-memory list, keeping the parallel arrays and
# BROKEN_START consistent. No-op if the id isn't present.
_forget_session_row() {
    local target="$1"
    local -a ids=() disp=() dirs=() heads=()
    local i broken=-1 removed_at=-1

    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        if [[ "${SESSION_IDS[$i]}" == "$target" ]]; then
            removed_at=$i
            continue
        fi
        # The group header belongs to the row that carries it. Removing that
        # row would take the whole group's heading with it, so hand it to the
        # next survivor.
        local head="${SESSION_HEADERS[$i]}"
        if ((removed_at == i - 1)) && [[ -z "$head" ]]; then
            head="${SESSION_HEADERS[$removed_at]}"
        fi
        ids+=("${SESSION_IDS[$i]}")
        disp+=("${SESSION_DISPLAYS[$i]}")
        dirs+=("${SESSION_DIRS[$i]}")
        heads+=("$head")
        if ((BROKEN_START >= 0 && i == BROKEN_START)); then
            broken=$((${#ids[@]} - 1))
        fi
    done

    ((removed_at < 0)) && return 1

    # The +() form matters: expanding an empty array as "${a[@]}" is an unbound
    # variable under set -u on bash 4.3 and older, and removing the only row is
    # exactly the case that produces one.
    SESSION_IDS=("${ids[@]+"${ids[@]}"}")
    SESSION_DISPLAYS=("${disp[@]+"${disp[@]}"}")
    SESSION_DIRS=("${dirs[@]+"${dirs[@]}"}")
    SESSION_HEADERS=("${heads[@]+"${heads[@]}"}")
    BROKEN_START=$broken
    return 0
}

# Replace the row for $1 with a dimmed "deleting" version, leaving it in
# place. The delete is fast, but "fast" and "instant" are not the same thing:
# dropping the row the moment D is pressed left nothing on screen to say a
# delete had happened at all, so a delete and a mis-keyed cursor move looked
# identical. Only the display changes — the id, dir and header stay put, so
# the row can be restored if the delete fails.
#
# The previous display text is handed back in the global MARKED_ROW_BEFORE
# rather than echoed. Echoing would force the caller into `$(...)`, and a
# command substitution runs in a subshell: the array edit would be thrown away
# with it and the row would never actually render as deleting. Returns 1 if
# the id isn't present.
MARKED_ROW_BEFORE=""
_mark_session_deleting() {
    local target="$1"
    local i
    MARKED_ROW_BEFORE=""
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        if [[ "${SESSION_IDS[$i]}" == "$target" ]]; then
            MARKED_ROW_BEFORE="${SESSION_DISPLAYS[$i]}"
            SESSION_DISPLAYS[i]=$(_compose_row \
                "${NAV_C_DIM}${ICON_STATE_DELETING}${NAV_C_NORMAL}" \
                "${NAV_C_DIM}$(_session_label "$target") — deleting…${NAV_C_NORMAL}" \
                "")
            return 0
        fi
    done
    return 1
}

# Put a freshly created session into the list right away, as a "starting"
# row, seated in its project group. n/f/N register a session and select it,
# but the arrays are only refreshed by the background rebuild — so for a
# second or two the list did not contain the row at all, and the cursor
# lookup fell back to row 0. The row used to be appended at the very bottom
# and left for the rebuild to move; the user watched it jump (#46). The
# caller knows the dir for n/f, and for N the metadata save_metadata has just
# written knows it, so the row goes where the rebuild will keep it: the end
# of its group, or a new headed group in name order. Starting (◐) is the
# honest icon — the session exists but has not written a transcript yet.
#
# launch_dir is used only to pick the seat. Dead/lost decisions stay with the
# transcript (get_session_cwd), as the Key API requires.
#
# Returns 1 if the id is already present, so a caller cannot double-add.
_remember_session_row() {
    local id="$1" dir="${2:-}"
    local i
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        [[ "${SESSION_IDS[$i]}" == "$id" ]] && return 1
    done
    # Resolve the dir the same way the rebuild will (_session_dir: transcript
    # cwd, then launch_dir), so the seat is where the rebuild keeps the row.
    # Callers that only know a *default* (n's picker default) pass "" rather
    # than guess — the user may have picked another directory entirely.
    [[ -z "$dir" ]] && dir=$(_session_dir "$id")

    # Live rows end where the broken tail starts; a live row never sits in it.
    local n=${#SESSION_IDS[@]}
    local live_end=$n
    ((BROKEN_START >= 0)) && live_end=$BROKEN_START

    # Within a group the rebuild keeps list-sessions order, which is tmux's
    # name order (strcmp on tower_<uuid>) — not creation order. Seat the row
    # where that order puts it, or it moves inside its group a tick later.
    local at=-1 header="" in_group=0 placed=0
    for ((i = 0; i < live_end; i++)); do
        [[ "${SESSION_DIRS[$i]}" == "$dir" ]] || continue
        in_group=1
        ((placed)) && continue
        if [[ "$id" < "${SESSION_IDS[$i]}" ]]; then
            at=$i
            placed=1
        else
            at=$((i + 1))
        fi
    done
    if ((in_group == 1)) && ((at < live_end)) && [[ "${SESSION_DIRS[$at]}" == "$dir" && -n "${SESSION_HEADERS[$at]}" ]]; then
        # Taking the group's first seat: the header rides on the first row,
        # so it moves to the new row and the old first row loses it.
        header="${SESSION_HEADERS[$at]}"
        SESSION_HEADERS[at]=""
    fi
    if ((in_group == 0)); then
        # No group yet: open one, placed by the same order the rebuild uses.
        header=$(_compose_group_header "$dir" 0)
        at=$live_end
        for ((i = 0; i < live_end; i++)); do
            [[ -n "${SESSION_HEADERS[$i]}" ]] || continue
            if _group_sorts_before "$dir" "${SESSION_DIRS[$i]}"; then
                at=$i
                break
            fi
        done
    fi

    local display
    display=$(_compose_row \
        "${NAV_C_DIM}${ICON_STATE_STARTING}${NAV_C_NORMAL}" \
        "$(_session_label "$id")" \
        "")

    local -a ids=() disp=() dirs=() heads=()
    for ((i = 0; i < n; i++)); do
        if ((i == at)); then
            ids+=("$id"); disp+=("$display"); dirs+=("$dir"); heads+=("$header")
        fi
        ids+=("${SESSION_IDS[$i]}")
        disp+=("${SESSION_DISPLAYS[$i]}")
        dirs+=("${SESSION_DIRS[$i]}")
        heads+=("${SESSION_HEADERS[$i]}")
    done
    if ((at >= n)); then
        ids+=("$id"); disp+=("$display"); dirs+=("$dir"); heads+=("$header")
    fi
    SESSION_IDS=("${ids[@]}")
    SESSION_DISPLAYS=("${disp[@]}")
    SESSION_DIRS=("${dirs[@]}")
    SESSION_HEADERS=("${heads[@]}")
    ((BROKEN_START >= 0)) && BROKEN_START=$((BROKEN_START + 1))
    return 0
}

# Re-draw an existing row as "starting" (◐). Restoring a session used to show
# nothing at all until the next rebuild landed, so pressing r looked like it
# had done nothing for a second or two. The session is genuinely starting at
# this point — it has been launched but has not written a transcript yet — so
# this is the same honest state a brand-new session gets. Returns 1 if the id
# isn't present.
_mark_session_starting() {
    local target="$1"
    local i
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        if [[ "${SESSION_IDS[$i]}" == "$target" ]]; then
            SESSION_DISPLAYS[i]=$(_compose_row \
                "${NAV_C_DIM}${ICON_STATE_STARTING}${NAV_C_NORMAL}" \
                "$(_session_label "$target")" \
                "")
            return 0
        fi
    done
    return 1
}

# Put back the display text _mark_session_deleting replaced, for when the
# delete fails and the session is still there.
_restore_session_row() {
    local target="$1" before="$2"
    local i
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        if [[ "${SESSION_IDS[$i]}" == "$target" ]]; then
            SESSION_DISPLAYS[i]="$before"
            return 0
        fi
    done
    return 1
}

# Redraw now, then let the background rebuild reconcile. Callers pass the
# index they want the cursor left on; it is clamped to the list and handed
# back in NAV_NEW_INDEX (and echoed, for callers that only want to read it).
#
# Call it BARE, never inside command substitution: it bumps the generation,
# resets the rebuild cool-off and records the rebuild PID, and every one of
# those is a global write that a subshell throws away. That is exactly how
# the generation guard was silently defeated — the parent's counter never
# moved, so every settle wrote the same "1" and a rebuild from before the
# first edit could publish over the second.
_settle_after_change() {
    local want="${1:-0}"
    local n=${#SESSION_IDS[@]}
    # Every caller has just changed the list optimistically. Bump first, so a
    # rebuild that started before the change cannot publish over it.
    _bump_list_generation
    # Then write what the screen now shows into the cache. The generation only
    # stops a *rebuild* from publishing a pre-edit snapshot; it does nothing
    # about the pre-edit snapshot already sitting in the cache file, which the
    # next refresh tick loads wholesale. Without this, a deleted row came back
    # on the next tick and left again when the forced rebuild landed — the
    # list looked like it had changed its mind. The cache is "what the list
    # shows", so an optimistic edit has to publish exactly like a rebuild.
    _publish_rebuild "$LIST_GENERATION" || true
    ((want < 0)) && want=0
    ((n > 0 && want >= n)) && want=$((n - 1))
    if ((n > 0)); then
        set_nav_selected "${SESSION_IDS[$want]}"
        signal_view_update_async
    else
        set_nav_selected ""
    fi
    # The user changed something and the confirmation should not lag: run
    # the rebuild now, or queue one behind the rebuild already running.
    _spawn_background_rebuild force
    NAV_NEW_INDEX="$want"
    echo "$want"
}
