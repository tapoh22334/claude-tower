#!/usr/bin/env bash
# navigator-list.sh - Left pane: Session list with vim-style navigation
#
# This script runs in the left pane of Navigator.
# It displays the session list and handles navigation keys.
# When switching sessions, it updates the state file and signals the right pane.

# Use pipefail but handle errors gracefully instead of exiting
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Error handler - log and continue instead of exiting
handle_script_error() {
    local line="$1"
    error_log "navigator-list.sh: Error at line $line"
    # Don't exit - the main loop will continue
}

trap 'handle_script_error $LINENO' ERR

# ============================================================================
# Configuration
# ============================================================================

# Spinner cadence: while idle the loop wakes every TICK_INTERVAL to advance
# the busy spinner (a pure string-substitution redraw); the session list
# itself is only rebuilt every TICKS_PER_REFRESH ticks (= 2s, the old
# REFRESH_INTERVAL).
readonly TICK_INTERVAL=0.25
readonly TICKS_PER_REFRESH=8
readonly -a SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧')
# Placeholder embedded in busy rows at build time, replaced with the current
# frame at render time so the spinner turns without rebuilding the list.
readonly SPIN_PLACEHOLDER='@@SPIN@@'
readonly ICON_UNREAD='✱'
SPIN_TICK=0

# Colors for navigator (using $'...' syntax for actual escape sequences)
readonly NAV_C_HEADER=$'\033[1;36m'
readonly NAV_C_SELECTED=$'\033[7m' # Reverse video
readonly NAV_C_NORMAL=$'\033[0m'
readonly NAV_C_DIM=$'\033[2m'
readonly NAV_C_ACCENT=$'\033[1;32m'  # Green bold - for highlights
readonly NAV_C_ERROR=$'\033[1;31m'   # Red bold - for errors
readonly NAV_C_ACTIVE=$'\033[32m'    # Green - active sessions
readonly NAV_C_DORMANT=$'\033[90m'   # Gray - dormant sessions

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

readonly NAV_C_EXTERNAL=$'\033[36m'  # Cyan - running outside Tower

# Row label inside a project group: the group header already names the
# directory, so the row shows the conversation title (what distinguishes
# sessions sharing a project), plus " (name)" when the registry has one.
_session_label() {
    local session_id="$1"
    local claude_id="${session_id#tower_}"
    local label="" name=""

    # A registry name is the user's own words for this session — when one
    # exists it IS the label, no title needed.
    if load_metadata "$session_id" 2>/dev/null && [[ -n "$META_SESSION_NAME" ]]; then
        name="$META_SESSION_NAME"
    fi
    label=$(get_session_title "$claude_id" 2>/dev/null) || label=""
    [[ -z "$label" ]] && label="${claude_id:0:7}"

    # Budget: terminal width minus the icon, indent and unread mark. Cut by
    # display cells — a Japanese title counted in characters overflows the
    # row and wraps onto a second line.
    local width budget
    width=$(tput cols 2>/dev/null || echo 80)
    budget=$((width - 8))
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

# Project dir of a session ("" when unknown)
_session_dir() {
    local claude_id="${1#tower_}" jsonl
    jsonl=$(find_session_jsonl "$claude_id" 2>/dev/null) || { echo ""; return 0; }
    get_session_cwd "$jsonl" 2>/dev/null || echo ""
}

# Build session list: normal states first, broken (dead/lost) last.
build_session_list() {
    SESSION_IDS=()
    SESSION_DISPLAYS=()
    SESSION_DIRS=()
    SESSION_HEADERS=()
    BROKEN_START=-1

    local -a raw_ids=() raw_displays=() raw_dirs=()
    local -a broken_ids=() broken_displays=()
    local session_id state label selected unread dir jsonl agents badge

    # The selected session is on screen in the view pane: whatever it has
    # produced counts as seen. Everything else gets a baseline mark so a
    # later busy->stop transition can be flagged as unread.
    selected=$(get_nav_selected)

    while IFS=: read -r session_id state; do
        [[ -z "$session_id" ]] && continue
        if [[ "$session_id" == "$selected" ]]; then
            mark_session_seen "$session_id"
        else
            init_session_seen "$session_id"
        fi
        unread=""
        if [[ "$state" == "active" || "$state" == "dormant" || "$state" == "external" ]] &&
            is_session_unread "$session_id"; then
            unread=" ${NAV_C_ACCENT}${ICON_UNREAD}${NAV_C_NORMAL}"
        fi
        label=$(_session_label "$session_id")
        dir=$(_session_dir "$session_id")
        case "$state" in
            busy)
                badge=""
                if jsonl=$(find_session_jsonl "${session_id#tower_}" 2>/dev/null); then
                    agents=$(count_active_subagents "$jsonl")
                    if [[ "$agents" -gt 0 ]]; then
                        badge=" ${NAV_C_DIM}⚙${agents}${NAV_C_NORMAL}"
                    fi
                fi
                raw_ids+=("$session_id")
                raw_dirs+=("$dir")
                raw_displays+=("${NAV_C_ACCENT}${SPIN_PLACEHOLDER}${NAV_C_NORMAL} ${label}${badge}")
                ;;
            active)
                raw_ids+=("$session_id")
                raw_dirs+=("$dir")
                raw_displays+=("${NAV_C_ACTIVE}▶${NAV_C_NORMAL} ${label}${unread}")
                ;;
            external)
                raw_ids+=("$session_id")
                raw_dirs+=("$dir")
                raw_displays+=("${NAV_C_EXTERNAL}◇${NAV_C_NORMAL} ${label}${unread}")
                ;;
            dormant)
                raw_ids+=("$session_id")
                raw_dirs+=("$dir")
                raw_displays+=("${NAV_C_DORMANT}○${NAV_C_NORMAL} ${label}${unread}")
                ;;
            dead)
                broken_ids+=("$session_id")
                broken_displays+=("${NAV_C_ERROR}✗${NAV_C_NORMAL} ${label}")
                ;;
            lost)
                broken_ids+=("$session_id")
                broken_displays+=("${NAV_C_ERROR}?${NAV_C_NORMAL} ${label}")
                ;;
        esac
    done < <(list_all_sessions)

    # Regroup by project dir: groups in first-appearance order, original
    # order kept within a group. Headers are precomputed here so spinner
    # ticks can re-render without touching the process table.
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

        # The project name is the one thing that must be findable at a
        # glance, so it gets the strongest treatment on screen: bold cyan
        # against dim rows, with a rule running out to the right margin.
        local dname rule_w
        dname=$(basename -- "${d:-unknown}")
        header="${NAV_C_HEADER}${dname}${NAV_C_NORMAL}"
        extern=$(count_unregistered_processes_in_dir "$d")
        if [[ "$extern" -gt 0 ]]; then
            # Live claude processes here that Tower doesn't manage
            # (forks / sessions started in plain terminals).
            header+=" ${NAV_C_EXTERNAL}⚡${extern}${NAV_C_NORMAL}"
        fi
        rule_w=$(( $(tput cols 2>/dev/null || echo 80) - $(str_display_width "$dname") - 4 ))
        if ((extern > 0)); then rule_w=$((rule_w - 3)); fi
        if ((rule_w > 0)); then
            local rule=""
            while ((${#rule} < rule_w)); do rule+="─"; done
            header+=" ${NAV_C_DIM}${rule}${NAV_C_NORMAL}"
        fi

        for ((j = i; j < ${#raw_ids[@]}; j++)); do
            if [[ "${raw_dirs[$j]}" == "$d" ]]; then
                SESSION_IDS+=("${raw_ids[$j]}")
                SESSION_DISPLAYS+=("${raw_displays[$j]}")
                SESSION_DIRS+=("$d")
                SESSION_HEADERS+=("$header")
                header=""
            fi
        done
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

# ============================================================================
# Rendering
# ============================================================================

# Render session list (double-buffered to prevent flicker)
render_list() {
    local selected_index="$1"
    local term_height
    term_height=$(tput lines 2>/dev/null || echo 24)
    # Row budget for the body (session rows + group headers + separator).
    # Reserve: header (2) + footer (2). If the frame is even one line
    # taller than the terminal, every redraw scrolls the screen and the
    # refresh loop turns into an endless upward crawl.
    local max_lines=$((term_height - 4))
    [[ $max_lines -lt 1 ]] && max_lines=1

    # Build output in variable first (double buffering)
    local output=""

    # Get current focus state
    local focus
    focus=$(get_nav_focus)

    # Focus indicator
    local focus_indicator=""
    if [[ "$focus" == "list" ]]; then
        focus_indicator="${NAV_C_ACCENT}[ACTIVE]${NAV_C_NORMAL}"
    else
        focus_indicator="${NAV_C_DIM}[─────]${NAV_C_NORMAL}"
    fi

    # Every line ends with \033[K (clear-to-end-of-line) before the newline.
    # Without it, a row left over from a longer previous render (e.g. the
    # multi-line help screen) keeps its old trailing characters when this
    # frame's line is shorter or blank — writing "\n" alone only moves the
    # cursor down, it does not erase what was already on that row. The
    # trailing `tput ed` below only clears rows *after* the last line we
    # print, so it can't fix a stale row sitting in the middle of the screen.
    local eol=$'\033[K'

    # Header with focus indicator
    output+="${NAV_C_HEADER}Sessions${NAV_C_NORMAL} ${focus_indicator}${eol}\n"
    output+="${eol}\n"

    if [[ ${#SESSION_IDS[@]} -eq 0 ]]; then
        output+="${NAV_C_DIM}(no sessions)${NAV_C_NORMAL}${eol}\n"
    else
        # Compose body lines first (group headers, separator, session rows)
        # so the height budget and "+N more" stay exact with headers in
        # the mix. body_idx maps each line to its session index (-1 = not
        # a session row).
        local spin_frame="${SPINNER_FRAMES[$((SPIN_TICK % ${#SPINNER_FRAMES[@]}))]}"
        local -a body_lines=() body_idx=()
        local i display
        for ((i = 0; i < ${#SESSION_IDS[@]}; i++)); do
            if [[ $BROKEN_START -ge 0 && $i -eq $BROKEN_START ]]; then
                body_lines+=("${NAV_C_DIM}── unrecoverable ──${NAV_C_NORMAL}")
                body_idx+=(-1)
            fi
            if [[ -n "${SESSION_HEADERS[$i]:-}" ]]; then
                body_lines+=("${SESSION_HEADERS[$i]}")
                body_idx+=(-1)
            fi
            display="${SESSION_DISPLAYS[$i]//$SPIN_PLACEHOLDER/$spin_frame}"
            if [[ $i -eq $selected_index ]]; then
                body_lines+=("${NAV_C_SELECTED}  ${display} ${NAV_C_NORMAL}")
            else
                body_lines+=("  ${display}")
            fi
            body_idx+=("$i")
        done

        local total=${#body_lines[@]}
        local shown=$total
        if [[ $total -gt $max_lines ]]; then
            shown=$((max_lines - 1))   # keep one row for "+N more"
            [[ $shown -lt 1 ]] && shown=1
        fi
        local n
        for ((n = 0; n < shown; n++)); do
            output+="${body_lines[$n]}${eol}\n"
        done
        if [[ $shown -lt $total ]]; then
            # Count hidden *sessions*, not hidden lines
            local hidden=0
            for ((n = shown; n < total; n++)); do
                if [[ "${body_idx[$n]}" -ge 0 ]]; then hidden=$((hidden + 1)); fi
            done
            output+="${NAV_C_DIM}... +${hidden} more${NAV_C_NORMAL}${eol}\n"
        fi
    fi

    # Footer with keybindings (compact). No trailing \n on the last line:
    # if the frame fills the terminal exactly, a final newline would still
    # scroll the screen by one row on every redraw.
    output+="${eol}\n"
    output+="${NAV_C_DIM}j/k:nav Enter/i:input n:add f:fork N:new-dir D:del r:resume t:tail q:quit${NAV_C_NORMAL}${eol}"

    # Clear to end of screen code
    local clear_eos
    clear_eos=$(tput ed 2>/dev/null || printf '\033[J')

    # Single atomic write: hide cursor, move home, print, clear rest, show cursor
    printf '\033[?25l\033[H%b%s\033[?25h' "$output" "$clear_eos"
}

# Show help screen
show_help() {
    clear
    echo -e "${NAV_C_HEADER}Navigator Help${NAV_C_NORMAL}"
    echo ""
    echo "  Navigation:"
    echo "    j / ↓      Move down"
    echo "    k / ↑      Move up"
    echo "    g          Go to first session"
    echo "    G          Go to last session"
    echo ""
    echo "  Actions:"
    echo "    Enter / i  Focus view pane (input mode)"
    echo "    n          Add session (pick existing Claude session or start new)"
    echo "    f          Fork: new session in the selected session's directory"
    echo "    N          New session in a picked project directory"
    echo "    D          Delete from Tower (Claude's transcript is kept)"
    echo "    r          Resume selected dormant session"
    echo "    Tab        Switch to Tile view"
    echo "    t          Switch to Tail view (live output follow)"
    echo "    ?          Show this help"
    echo "    q          Quit Navigator"
    echo ""
    # Keep the help under 24 rows total: at 24 printed lines the final
    # newline scrolls the title off a default-size terminal.
    echo "  Marks:     ${SPINNER_FRAMES[0]} working  ${ICON_UNREAD} unread  ◇ external  ⚙N subagents  ⚡N unmanaged"
    echo ""
    echo -e "${NAV_C_DIM}Press any key to continue...${NAV_C_NORMAL}"
    read -rsn1
}

# ============================================================================
# Actions
# ============================================================================

# Signal view pane to update
# Uses tmux switch-client for instant session switching in inner tmux
signal_view_update() {
    local selected view_tty
    selected=$(get_nav_selected)

    if [[ -z "$selected" ]]; then
        return
    fi

    # Get the tty of the view pane (pane 1 in navigator session)
    view_tty=$(nav_tmux display-message -t "$TOWER_NAV_SESSION:0.1" -p '#{pane_tty}' 2>/dev/null)

    if [[ -z "$view_tty" ]]; then
        return
    fi

    # Use switch-client for instant session switching
    # This switches the inner tmux client to the new session without detach/re-attach cycle
    session_tmux switch-client -c "$view_tty" -t "$selected" 2>/dev/null || true
    debug_log "switch-client: tty=$view_tty session=$selected"

    # Signal the view pane via tmux wait-for (wakes up if waiting)
    nav_tmux wait-for -S "$TOWER_VIEW_UPDATE_CHANNEL" 2>/dev/null || true
}

# Move selection and update view
move_selection() {
    local direction="$1" # "up" or "down"
    local current_index="$2"
    local new_index

    if [[ "$direction" == "down" ]]; then
        new_index=$((current_index + 1))
        [[ $new_index -ge ${#SESSION_IDS[@]} ]] && new_index=0
    else
        new_index=$((current_index - 1))
        [[ $new_index -lt 0 ]] && new_index=$((${#SESSION_IDS[@]} - 1))
        [[ $new_index -lt 0 ]] && new_index=0
    fi

    if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
        local new_session="${SESSION_IDS[$new_index]}"
        set_nav_selected "$new_session"
        signal_view_update
    fi

    echo "$new_index"
}

# Go to first session
go_first() {
    if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
        set_nav_selected "${SESSION_IDS[0]}"
        signal_view_update
    fi
    echo 0
}

# Go to last session
go_last() {
    if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
        local last_index=$((${#SESSION_IDS[@]} - 1))
        set_nav_selected "${SESSION_IDS[$last_index]}"
        signal_view_update
        echo "$last_index"
    else
        echo 0
    fi
}

# Focus on view pane (enables input to selected session)
# Simply moves tmux pane focus - no mode switching needed since view always attaches in input mode
focus_view() {
    set_nav_focus "view"
    nav_tmux select-pane -t "$TOWER_NAV_SESSION:0.1"
}

# Unified add/new flow (session-add.sh). Runs interactively in this pane;
# fzf draws on the tty, the chosen tower_<id> comes back on stdout.
add_session_inline() {
    clear
    local new_id
    new_id=$(TOWER_ADD_DEFAULT_DIR="$(get_caller_cwd)" "$SCRIPT_DIR/session-add.sh" --print-id) || {
        return 0  # cancelled or failed; messages already shown
    }
    if [[ -n "$new_id" ]]; then
        set_nav_selected "$new_id"
        signal_view_update
    fi
}

# Fork here: start a brand-new session in the selected session's project
# dir, no prompts. The new session is registered and selected.
fork_session_here() {
    local selected dir new_id
    selected=$(get_nav_selected)
    if [[ -z "$selected" ]]; then
        return 0
    fi
    dir=$(_session_dir "$selected")
    if [[ -z "$dir" || ! -d "$dir" ]]; then
        echo ""
        echo "  ${NAV_C_DIM}No directory known for this session${NAV_C_NORMAL}"
        sleep 0.5
        return 0
    fi
    clear
    new_id=$("$SCRIPT_DIR/session-add.sh" --fork-dir "$dir" --print-id) || return 0
    if [[ -n "$new_id" ]]; then
        set_nav_selected "$new_id"
        signal_view_update
    fi
}

# Pick a known project directory and start a new session there.
new_session_pick_dir() {
    clear
    local new_id
    new_id=$("$SCRIPT_DIR/session-add.sh" --new-in-dir --print-id) || return 0
    if [[ -n "$new_id" ]]; then
        set_nav_selected "$new_id"
        signal_view_update
    fi
}

# Working directory of the caller pane (default dir for new sessions)
get_caller_cwd() {
    local caller cwd=""
    caller=$(get_nav_caller)
    if [[ -n "$caller" ]]; then
        cwd=$(session_tmux display-message -t "$caller" -p '#{pane_current_path}' 2>/dev/null) ||
            cwd=$(TMUX= tmux display-message -t "$caller" -p '#{pane_current_path}' 2>/dev/null) ||
            cwd=""
    fi
    echo "${cwd:-$HOME}"
}

# Delete selected session
delete_selected() {
    local selected
    selected=$(get_nav_selected)

    if [[ -z "$selected" ]]; then
        return
    fi

    local name="${selected#tower_}"
    local term_height
    term_height=$(tput lines 2>/dev/null || echo 24)

    # Move cursor to bottom of list area and show confirmation UI
    tput cup "$((term_height - 5))" 0 2>/dev/null || true
    echo -e "${NAV_C_HEADER}┌─ Delete Session ────────┐${NAV_C_NORMAL}"
    echo -e "│ Session: ${NAV_C_ACCENT}${name}${NAV_C_NORMAL}"
    printf "│ Confirm? [y/n]: "

    local confirm=""
    if ! read -rsn1 -t 10 confirm; then
        echo ""
        echo -e "│ ${NAV_C_DIM}Cancelled (timeout)${NAV_C_NORMAL}"
        echo -e "${NAV_C_HEADER}└─────────────────────────┘${NAV_C_NORMAL}"
        sleep 0.5
        return
    fi
    echo ""

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo -e "│ ${NAV_C_DIM}Deleting...${NAV_C_NORMAL}"
        if TOWER_QUIET_ERRORS=1 "$SCRIPT_DIR/session-delete.sh" "$selected" --force 2>/dev/null; then
            echo -e "│ ${NAV_C_ACCENT}✓${NAV_C_NORMAL} Deleted"
        else
            echo -e "│ ${NAV_C_ERROR}✗${NAV_C_NORMAL} Delete failed"
        fi
    else
        echo -e "│ ${NAV_C_DIM}Cancelled${NAV_C_NORMAL}"
    fi
    echo -e "${NAV_C_HEADER}└─────────────────────────┘${NAV_C_NORMAL}"
    sleep 0.5
}

# Restore selected session (idempotent)
# - dormant → restore
# - active → do nothing (already active)
# - no metadata → do nothing (can't restore)
restore_selected() {
    local selected
    selected=$(get_nav_selected)

    if [[ -z "$selected" ]]; then
        return 0
    fi

    # Check if session already exists (active) on session server
    if session_tmux has-session -t "$selected" 2>/dev/null; then
        # Already active - idempotent success
        echo ""
        echo "  ${NAV_C_DIM}Already active${NAV_C_NORMAL}"
        sleep 0.3
        return 0
    fi

    # Check if metadata exists (can restore)
    if ! has_metadata "$selected"; then
        # No metadata - can't restore
        echo ""
        echo "  ${NAV_C_DIM}Not registered — press n to add${NAV_C_NORMAL}"
        sleep 0.3
        return 0
    fi

    # Already running outside Tower's tmux: resuming would open a second
    # copy of a live session.
    if [[ "$(get_display_state "$selected")" == "external" ]]; then
        echo ""
        echo "  ${NAV_C_DIM}Running outside Tower (◇) — use its own terminal${NAV_C_NORMAL}"
        sleep 0.5
        return 0
    fi

    # Dormant - restore it
    echo ""
    echo "  ${NAV_C_ACCENT}Restoring...${NAV_C_NORMAL}"

    if "$SCRIPT_DIR/session-restore.sh" "$selected" 2>/dev/null; then
        echo "  ${NAV_C_ACCENT}✓${NAV_C_NORMAL} Restored: ${selected#tower_}"
        signal_view_update
    else
        echo "  ${NAV_C_ERROR}✗${NAV_C_NORMAL} Failed to restore"
    fi
    sleep 0.5
}

# Switch to Tile mode
switch_to_tile() {
    info_log "Switching to Tile mode"

    # Create tile window on session server (where Claude sessions live)
    session_tmux new-window -n "tower-tile" "$SCRIPT_DIR/tile.sh" 2>/dev/null || true

    # Get the first available session on session server
    local target_session
    target_session=$(session_tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")

    if [[ -n "$target_session" ]]; then
        # Detach from Navigator and attach to session server
        nav_tmux detach-client -E "TMUX= tmux -L '$TOWER_SESSION_SOCKET' attach-session -t '$target_session'"
    fi
}

# Switch to Tail view (live multi-session output follow)
switch_to_tail() {
    info_log "Switching to Tail mode"

    # Create tail window on session server (where Claude sessions live)
    session_tmux new-window -n "tower-tail" "$SCRIPT_DIR/tail-view.sh" 2>/dev/null || true

    local target_session
    target_session=$(session_tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")

    if [[ -n "$target_session" ]]; then
        nav_tmux detach-client -E "TMUX= tmux -L '$TOWER_SESSION_SOCKET' attach-session -t '$target_session'"
    fi
}

# Quit Navigator
# Returns to the caller session or any available session on default server
quit_navigator() {
    local caller
    caller=$(get_nav_caller)

    info_log "Quitting Navigator, returning to caller: ${caller:-<none>}"

    # Determine target session - check session server first, then fall back to default server
    local target_session=""
    local target_socket=""

    if [[ -n "$caller" ]]; then
        if session_tmux has-session -t "$caller" 2>/dev/null; then
            target_session="$caller"
            target_socket="$TOWER_SESSION_SOCKET"
        elif TMUX= tmux has-session -t "$caller" 2>/dev/null; then
            target_session="$caller"
            target_socket=""  # default server
        fi
    fi

    # Fallback: find any session on session server first, then default server
    if [[ -z "$target_session" ]]; then
        target_session=$(session_tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")
        [[ -n "$target_session" ]] && target_socket="$TOWER_SESSION_SOCKET"
    fi
    if [[ -z "$target_session" ]]; then
        target_session=$(TMUX= tmux list-sessions -F '#{session_name}' 2>/dev/null | head -1 || echo "")
        target_socket=""
    fi

    if [[ -n "$target_session" ]]; then
        # Use detach-client -E to seamlessly return to appropriate server
        if [[ -n "$target_socket" ]]; then
            nav_tmux detach-client -E "TMUX= tmux -L '$target_socket' attach-session -t '$target_session'"
        else
            nav_tmux detach-client -E "TMUX= tmux attach-session -t '$target_session'"
        fi
    else
        # No sessions available, just exit
        nav_tmux detach-client
    fi
}

# ============================================================================
# Main Loop
# ============================================================================

main_loop() {
    # Initial build
    build_session_list

    # Validate current selection - clear if session no longer exists
    local current_selected
    current_selected=$(get_nav_selected)
    if [[ -n "$current_selected" ]]; then
        local found=0
        for id in "${SESSION_IDS[@]:-}"; do
            [[ "$id" == "$current_selected" ]] && { found=1; break; }
        done
        if [[ $found -eq 0 ]]; then
            # Selected session no longer exists, clear selection
            set_nav_selected ""
        fi
    fi

    # Get initial selection
    local selected_index
    selected_index=$(get_selection_index)

    # Set initial selection if not set or invalid
    if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
        current_selected=$(get_nav_selected)
        if [[ -z "$current_selected" ]]; then
            set_nav_selected "${SESSION_IDS[0]}"
            signal_view_update
        fi
    fi

    # Initial clear and hide cursor during rendering
    clear

    while true; do
        # render_list handles cursor positioning internally
        render_list "$selected_index"

        # Wait for input with timeout (short tick so the spinner turns)
        local key=""
        if read -rsn1 -t "$TICK_INTERVAL" key; then
            case "$key" in
                j | $'\x1b')
                    # Handle arrow keys
                    if [[ "$key" == $'\x1b' ]]; then
                        read -rsn2 -t 0.1 arrow || true
                        case "$arrow" in
                            '[B') key="j" ;; # Down
                            '[A') key="k" ;; # Up
                            *) continue ;;
                        esac
                    fi
                    if [[ "$key" == "j" ]]; then
                        selected_index=$(move_selection "down" "$selected_index")
                    fi
                    ;;
                k)
                    selected_index=$(move_selection "up" "$selected_index")
                    ;;
                g)
                    selected_index=$(go_first)
                    ;;
                G)
                    selected_index=$(go_last)
                    ;;
                '') # Enter key - same as i
                    focus_view
                    ;;
                i)
                    focus_view
                    ;;
                n)
                    add_session_inline
                    # Flush input buffer and restore terminal state
                    read -rsn100 -t 0.01 _ 2>/dev/null || true
                    stty echo 2>/dev/null || true
                    build_session_list
                    selected_index=$(get_selection_index)
                    clear
                    ;;
                f)
                    fork_session_here
                    read -rsn100 -t 0.01 _ 2>/dev/null || true
                    stty echo 2>/dev/null || true
                    build_session_list
                    selected_index=$(get_selection_index)
                    clear
                    ;;
                N)
                    new_session_pick_dir
                    read -rsn100 -t 0.01 _ 2>/dev/null || true
                    stty echo 2>/dev/null || true
                    build_session_list
                    selected_index=$(get_selection_index)
                    clear
                    ;;
                D)
                    delete_selected
                    # Flush input buffer and restore terminal state
                    read -rsn100 -t 0.01 _ 2>/dev/null || true
                    stty echo 2>/dev/null || true
                    build_session_list
                    selected_index=$(get_selection_index)
                    clear  # Clear screen after input mode
                    ;;
                r)
                    # Restore selected dormant session
                    restore_selected
                    build_session_list
                    selected_index=$(get_selection_index)
                    clear
                    ;;
                $'\t') # Tab key
                    switch_to_tile
                    ;;
                t)
                    switch_to_tail
                    ;;
                '?')
                    show_help
                    # Flush input buffer after help
                    read -rsn100 -t 0.01 _ 2>/dev/null || true
                    ;;
                q | Q)
                    quit_navigator
                    ;;
            esac
        else
            # Timeout tick - advance the spinner; only rebuild the session
            # list (stat/grep per session) every TICKS_PER_REFRESH ticks.
            SPIN_TICK=$(((SPIN_TICK + 1) % 1000000))
            if [[ $((SPIN_TICK % TICKS_PER_REFRESH)) -ne 0 ]]; then
                continue
            fi
            build_session_list

            # Clamp selection
            if [[ $selected_index -ge ${#SESSION_IDS[@]} ]]; then
                selected_index=$((${#SESSION_IDS[@]} - 1))
                [[ $selected_index -lt 0 ]] && selected_index=0
                if [[ ${#SESSION_IDS[@]} -gt 0 ]]; then
                    set_nav_selected "${SESSION_IDS[$selected_index]}"
                fi
            fi
        fi
    done
}

# ============================================================================
# Main
# ============================================================================

# Only start the render loop when executed directly, so tests can source
# this file to reach its functions.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_loop
fi
