#!/usr/bin/env bash
# shellcheck shell=bash
# nav-jump.sh - `f` label jump (value/003-nav-keys), as in vimium.
#
# f puts a two-letter label left of every row. The first letter is the
# project's, a, b, c... from the top; the second is the row's place in its
# group, the project row itself first: project c is ca, its sessions cb,
# cc... Every row is two keys away. The first letter keeps only that
# project's labels, the second lands; Esc, Enter or a letter that labels
# nothing cancels.
#
# The labels belong to the list as it was when f was pressed: the row
# behind a label is remembered by id, so a list that changes underneath
# never sends the cursor to a row the person did not pick.

NAV_JUMP_ACTIVE=""
NAV_JUMP_PREFIX=""
declare -a NAV_JUMP_LABELS=()
declare -a NAV_JUMP_IDS=()

_JUMP_LETTERS="abcdefghijklmnopqrstuvwxyz"

# Label every row of the current list. Rows under "unrecoverable", rows
# outside any project, projects past the 26th and sessions past a
# project's 25th get none. Returns 1 when there is no project row to label.
_jump_assign_labels() {
    local i id project="" p=0 s=0 any=1
    NAV_JUMP_LABELS=()
    NAV_JUMP_IDS=()
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        id="${SESSION_IDS[$i]}"
        NAV_JUMP_IDS[i]="$id"
        NAV_JUMP_LABELS[i]=""
        if [[ $BROKEN_START -ge 0 && $i -ge $BROKEN_START ]]; then
            continue
        fi
        if _row_is_project "$id"; then
            project=""
            s=0
            if ((p < 26)); then
                project="${_JUMP_LETTERS:p:1}"
                NAV_JUMP_LABELS[i]="${project}a"
                any=0
            fi
            p=$((p + 1))
            s=1
            continue
        fi
        if [[ -n "$project" ]] && ((s < 26)); then
            NAV_JUMP_LABELS[i]="${project}${_JUMP_LETTERS:s:1}"
        fi
        s=$((s + 1))
    done
    return "$any"
}

# Is $1 one of the labels on screen?
_jump_has_label() {
    local l
    for l in "${NAV_JUMP_LABELS[@]}"; do
        [[ "$l" == "$1" ]] && return 0
    done
    return 1
}

# The label cell render_list puts left of row $1, in NAV_JUMP_CELL: three
# cells wide, blank for a row without a label or outside the chosen project.
NAV_JUMP_CELL=""
_jump_cell() {
    local l="${NAV_JUMP_LABELS[$1]:-}"
    if [[ -n "$NAV_JUMP_PREFIX" && "$l" != "$NAV_JUMP_PREFIX"* ]]; then
        l=""
    fi
    if [[ -z "$l" ]]; then
        NAV_JUMP_CELL="   "
        return 0
    fi
    printf -v NAV_JUMP_CELL '%s%-2s%s ' "$NAV_C_ACCENT" "$l" "$NAV_C_NORMAL"
}

# Fit body line $1 into $2 cells, in NAV_JUMP_FIT. Rows are composed to the
# full content width, so the 3-cell label column would push a row with
# right-aligned marks one cell row down and scroll the frame. The overflow
# comes out of the padding run before the marks; a line without one is cut.
NAV_JUMP_FIT=""
_jump_fit() {
    local line="$1" budget="$2" over run head tail
    _strip_ansi_into "$line"
    over=$(($(str_display_width "$NAV_STRIPPED") - budget))
    if ((over <= 0)); then
        NAV_JUMP_FIT="$line"
        return 0
    fi
    printf -v run '%*s' $((over + 1)) ''
    if [[ "$line" == *"$run"* ]]; then
        head="${line%"$run"*}"
        tail="${line#"$head"}"
        NAV_JUMP_FIT="${head}${tail:over}"
        return 0
    fi
    NAV_JUMP_FIT="$(truncate_display "$NAV_STRIPPED" "$budget")"
}

_jump_end() {
    NAV_JUMP_ACTIVE=""
    NAV_JUMP_PREFIX=""
}

# Move the cursor to the row labelled $1, found by the id it had when f was
# pressed. Leaves NAV_NEW_INDEX alone when that row is gone.
_jump_land() {
    local label="$1" i id=""
    for ((i = 0; i < ${#NAV_JUMP_LABELS[@]}; i++)); do
        if [[ "${NAV_JUMP_LABELS[$i]}" == "$label" ]]; then
            id="${NAV_JUMP_IDS[$i]}"
            break
        fi
    done
    [[ -n "$id" ]] || return 0
    for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
        if [[ "${SESSION_IDS[$i]}" == "$id" ]]; then
            NAV_NEW_INDEX="$i"
            set_nav_selected "$id"
            signal_view_update_async
            return 0
        fi
    done
    return 0
}

# The f key. Runs its own read loop, like `/`, so the list keeps redrawing
# with the labels on it. $1 = current index; the final index is left in
# NAV_NEW_INDEX (unchanged unless a label was completed).
jump_prompt() {
    local index="$1" key="" rc=0 prefix="" target=""
    NAV_NEW_INDEX="$index"
    _jump_assign_labels || return 0
    NAV_JUMP_ACTIVE=1
    NAV_JUMP_PREFIX=""
    while true; do
        render_list "$index"
        rc=0
        nav_read_key key "$TICK_INTERVAL" || rc=$?
        if [[ $rc -eq 2 ]]; then
            _jump_end
            exit 0
        fi
        if [[ $rc -ne 0 ]]; then
            SPIN_TICK=$(((SPIN_TICK + 1) % 1000000))
            _flush_pending_view_signal
            continue
        fi
        if [[ "$key" == $'\x1b' ]]; then
            # Esc cancels; drain an arrow's sequence so it does not leak
            # into the list as keys.
            nav_read_escape
            break
        fi
        if [[ -z "$prefix" ]] && _jump_has_label "${key}a"; then
            prefix="$key"
            NAV_JUMP_PREFIX="$prefix"
            continue
        fi
        if [[ -n "$prefix" ]] && _jump_has_label "$prefix$key"; then
            target="$prefix$key"
        fi
        break
    done
    _jump_end
    if [[ -n "$target" ]]; then
        _jump_land "$target"
    fi
    return 0
}
