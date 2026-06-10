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
source "$SCRIPT_DIR/../lib/tile.sh"

# Error handler - log and continue instead of exiting
handle_script_error() {
    local line="$1"
    error_log "navigator-list.sh: Error at line $line"
    # Don't exit - the main loop will continue
}

trap 'handle_script_error $LINENO' ERR

# Swallow SIGINT (Ctrl-C). The default behaviour terminates the script and
# leaves the user stranded in a dead pane. We'd rather treat Ctrl-C as a
# UI cancel and keep the navigator running.
trap ':' INT

# ============================================================================
# Configuration
# ============================================================================

readonly REFRESH_INTERVAL=2

# Colors for navigator (using $'...' syntax for actual escape sequences)
readonly NAV_C_HEADER=$'\033[1;36m'
readonly NAV_C_SELECTED=$'\033[7m' # Reverse video
readonly NAV_C_NORMAL=$'\033[0m'
readonly NAV_C_DIM=$'\033[2m'
readonly NAV_C_ACCENT=$'\033[1;32m' # Green bold - for highlights
readonly NAV_C_ERROR=$'\033[1;31m'  # Red bold - for errors
readonly NAV_C_ACTIVE=$'\033[32m'   # Green - active sessions
readonly NAV_C_DORMANT=$'\033[90m'  # Gray - dormant sessions

# Caller CWD state file (written by claude-tower.tmux on Navigator launch).
# Overridable via env var so tests can isolate state.
readonly NAV_CALLER_CWD_FILE="${CLAUDE_TOWER_CALLER_CWD_FILE:-/tmp/claude-tower/caller-cwd}"

# Claude Code's internal data locations. These are reverse-engineered, not
# a documented public API, so we treat them defensively (version checks,
# graceful fallback). Overridable for tests.
readonly NAV_CLAUDE_DIR="${CLAUDE_TOWER_CLAUDE_DIR:-$HOME/.claude}"
readonly NAV_CLAUDE_HISTORY="$NAV_CLAUDE_DIR/history.jsonl"
readonly NAV_CLAUDE_PROJECTS_DIR="$NAV_CLAUDE_DIR/projects"
readonly NAV_SESSIONS_INDEX_SUPPORTED_VERSION=1

# ============================================================================
# Caller Context
# ============================================================================

# Load the caller's working directory captured at Navigator launch.
# Falls back to $HOME if unavailable.
_load_caller_cwd() {
    local cwd=""
    if [[ -r "$NAV_CALLER_CWD_FILE" ]]; then
        cwd=$(<"$NAV_CALLER_CWD_FILE")
        cwd="${cwd//$'\n'/}" # strip newlines
    fi
    if [[ -z "$cwd" || ! -d "$cwd" ]]; then
        cwd="$HOME"
    fi
    echo "$cwd"
}

# ============================================================================
# Claude project history (for the new-session picker)
# ============================================================================
#
# These helpers read from Claude Code's internal data files
# (~/.claude/history.jsonl and ~/.claude/projects/*/sessions-index.json).
# Those files are NOT a documented public API — the schema was
# reverse-engineered from community write-ups. Every read is therefore
# defensive: if jq is unavailable we fall back to grep; if the
# `version` field changes from 1 we skip the file; if anything errors
# we silently return nothing and let the caller fall back to manual
# path entry.
#
# The intent is that an Anthropic-side format change can at worst
# degrade the picker to "empty list, please type the path" — never
# crash Navigator.

# Extract project paths from a JSON stream. Different Claude Code releases
# have used different key names — `projectPath` in older sessions-index
# entries, `project` in newer history.jsonl lines. We accept either,
# falling back to `cwd` if both are absent.
_extract_project_paths() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '(.projectPath // .project // .cwd // empty)' 2>/dev/null
    else
        # Match any of the three key names. The capturing group picks up
        # the value after the colon regardless of which key matched.
        grep -oE '"(projectPath|project|cwd)"[[:space:]]*:[[:space:]]*"[^"]*"' 2>/dev/null |
            sed -E 's/.*"(projectPath|project|cwd)"[[:space:]]*:[[:space:]]*"([^"]*)".*/\2/'
    fi
}

# Read project paths from the global history file (one JSON per line).
_load_history_paths() {
    [[ -r "$NAV_CLAUDE_HISTORY" ]] || return 0
    _extract_project_paths <"$NAV_CLAUDE_HISTORY" 2>/dev/null
}

# Read project paths from per-project sessions-index.json files.
# Only entries from files with a supported `version` are returned.
_load_sessions_index_paths() {
    [[ -d "$NAV_CLAUDE_PROJECTS_DIR" ]] || return 0

    local f ver
    # `ls -dt` gives us roughly recency-ordered dirs.
    for f in "$NAV_CLAUDE_PROJECTS_DIR"/*/sessions-index.json; do
        [[ -r "$f" ]] || continue

        if command -v jq >/dev/null 2>&1; then
            ver=$(jq -r '.version // 0' "$f" 2>/dev/null || echo 0)
            [[ "$ver" -eq "$NAV_SESSIONS_INDEX_SUPPORTED_VERSION" ]] || continue
            # Same key fallback as _extract_project_paths.
            jq -r '.entries[]? | (.projectPath // .project // .cwd // empty)' \
                "$f" 2>/dev/null
        else
            # Without jq we trust the file format; if it changes we get a
            # noisy list which is harmless — the picker filters out
            # non-existent directories before showing anything.
            _extract_project_paths <"$f" 2>/dev/null
        fi
    done
}

# Final picker source: unique existing directory paths, freshest first
# (by sessions-index file mtime), excluding paths already registered as
# tower sessions.
#
# Deduplication uses awk with !seen[] so first-encountered order is kept.
_load_claude_projects() {
    local registered_paths=""
    local id sid_path
    # Build a set of paths that are already registered as tower sessions.
    for id in "${SESSION_IDS[@]:-}"; do
        if load_metadata "$id" 2>/dev/null; then
            sid_path="$META_DIRECTORY_PATH"
            [[ -n "$sid_path" ]] && registered_paths+="$sid_path"$'\n'
        fi
    done

    {
        _load_sessions_index_paths
        _load_history_paths
    } 2>/dev/null |
        awk 'NF && !seen[$0]++' |
        while IFS= read -r p; do
            [[ -d "$p" ]] || continue
            # Skip already-registered paths
            if [[ -n "$registered_paths" ]] && grep -qxF "$p" <<<"$registered_paths"; then
                continue
            fi
            echo "$p"
        done
}

# ============================================================================
# Session List Management
# ============================================================================

# Session arrays
declare -a SESSION_IDS=()
declare -a SESSION_DISPLAYS=()

# Build session list from default tmux server
# v2: Shows path instead of type icon
# Idempotent: Uses has-session logic (tmux session exists = active)
build_session_list() {
    SESSION_IDS=()
    SESSION_DISPLAYS=()

    local -A active_sessions=()

    # Get active tower sessions from DEFAULT tmux server (not Navigator server)
    while IFS= read -r session_id; do
        [[ -z "$session_id" ]] && continue
        [[ "$session_id" != tower_* ]] && continue

        active_sessions["$session_id"]=1

        local name short_path=""
        name="${session_id#tower_}"

        # Load path from metadata (v2 format)
        if load_metadata "$session_id" 2>/dev/null; then
            short_path=$(shorten_path "$META_DIRECTORY_PATH")
        fi

        SESSION_IDS+=("$session_id")
        # v2 format: state_icon name  path
        SESSION_DISPLAYS+=("${NAV_C_ACTIVE}▶${NAV_C_NORMAL} ${name}  ${NAV_C_DIM}${short_path}${NAV_C_NORMAL}")
    done < <(session_tmux list-sessions -F '#{session_name}' 2>/dev/null || true)

    # Add dormant sessions (metadata exists but no tmux session)
    for meta_file in "${TOWER_METADATA_DIR}"/*.meta; do
        [[ -f "$meta_file" ]] || continue

        local session_id
        session_id=$(basename "$meta_file" .meta)

        # Skip if already in list (active session)
        [[ -n "${active_sessions[$session_id]:-}" ]] && continue

        local name short_path=""
        name="${session_id#tower_}"

        # Load path from metadata (v2 format)
        if load_metadata "$session_id" 2>/dev/null; then
            short_path=$(shorten_path "$META_DIRECTORY_PATH")
        fi

        SESSION_IDS+=("$session_id")
        # v2 format: state_icon name  path
        SESSION_DISPLAYS+=("${NAV_C_DORMANT}○${NAV_C_NORMAL} ${name}  ${NAV_C_DIM}${short_path}${NAV_C_NORMAL}")
    done
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
    local max_lines=$((term_height - 4)) # Reserve space for footer

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

    # Header with focus indicator
    output+="${NAV_C_HEADER}Sessions${NAV_C_NORMAL} ${focus_indicator}\n"

    # Surface a pending warning (e.g. an incomplete Tile teardown) once.
    local warning
    warning=$(get_nav_warning)
    if [[ -n "$warning" ]]; then
        output+="${NAV_C_ACCENT}⚠ ${warning}${NAV_C_NORMAL}\n"
    fi

    output+="\n"

    if [[ ${#SESSION_IDS[@]} -eq 0 ]]; then
        output+="${NAV_C_DIM}(no sessions)${NAV_C_NORMAL}\n"
    else
        local i=0
        for display in "${SESSION_DISPLAYS[@]}"; do
            if [[ $i -ge $max_lines ]]; then
                local remaining=$((${#SESSION_IDS[@]} - max_lines))
                output+="${NAV_C_DIM}... +${remaining} more${NAV_C_NORMAL}\n"
                break
            fi

            if [[ $i -eq $selected_index ]]; then
                # Highlight selected row
                output+="${NAV_C_SELECTED} ${display} ${NAV_C_NORMAL}\n"
            else
                output+=" ${display}\n"
            fi
            ((i++)) || true
        done
    fi

    # Footer with keybindings (compact)
    output+="\n"
    output+="${NAV_C_DIM}j/k:nav  1-9:jump  Enter:attach  i:input  n:new  d:del  r:restore  ?:help  q:quit${NAV_C_NORMAL}\n"

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
    echo "    1-9        Jump to Nth session (first 9 only)"
    echo ""
    echo "  Actions:"
    echo "    Enter      Full attach to session"
    echo "    i          Focus view pane (input mode)"
    echo "    n          New session (prompts for path, prefilled with caller CWD)"
    echo "    d          Delete selected session (with [y/N] confirm)"
    echo "    r          Restore selected dormant session"
    echo "    R          Restore all dormant sessions"
    echo "    Tab        Enter Tile view (all sessions side-by-side)"
    echo ""
    echo "  In Tile view:"
    echo "    prefix+Tab Return to Navigator (focused session selected)"
    echo "    prefix+z   Zoom focused pane to fullscreen (and back)"
    echo "    prefix+→/← Move between panes"
    echo "    prefix+t   Leave Tower entirely"
    echo ""
    echo "  Other:"
    echo "    ?          Show this help"
    echo "    q          Quit Navigator"
    echo "    prefix+t   Leave Tower entirely"
    echo ""
    echo -e "${NAV_C_DIM}Press any key to continue...${NAV_C_NORMAL}"
    read -rsn1
}

# ============================================================================
# Inline Prompts
# ============================================================================

# Render a single-line input prompt at the bottom of the pane.
# Uses readline editing (-e) with a prefilled default.
# Returns the user's input on stdout. Empty string means cancelled (empty input
# or readline EOF).
#
# Implementation note: terminal control sequences (cursor position, visibility)
# go to /dev/tty so they reach the pane WITHOUT polluting stdout when the
# caller uses command substitution: path=$(_prompt_inline ...).
_prompt_inline() {
    local label="$1"
    local default="${2:-}"
    local term_height
    term_height=$(tput lines 2>/dev/null || echo 24)

    # Move to bottom line, clear it, show cursor (terminal-only side effects).
    printf '\033[%d;1H\033[2K\033[?25h' "$term_height" >/dev/tty

    # Make Ctrl-W delete the previous path segment (separator-aware) rather
    # than wiping the whole line. The default unix-word-rubout treats `/`
    # as part of a word so a path with no spaces gets nuked in one stroke.
    # `backward-kill-word` honours `/` as a delimiter.
    bind '"\C-w": backward-kill-word' 2>/dev/null || true

    local result=""
    # Read with readline editing, prefilled with default. Prompt (-p) writes
    # to stderr in bash, so it doesn't get into the captured stdout either.
    # Returns non-zero on EOF/Ctrl-C; treat as cancellation.
    if ! IFS= read -r -e -i "$default" -p "$label" result; then
        result=""
    fi

    # Hide cursor again to match Navigator's normal state (terminal-only).
    printf '\033[?25l' >/dev/tty

    echo "$result"
}

# Render a single-char y/N confirmation prompt at the bottom of the pane.
# Returns 0 (yes) only if user presses lowercase 'y'; non-zero otherwise.
_prompt_yesno_inline() {
    local label="$1"
    local term_height
    term_height=$(tput lines 2>/dev/null || echo 24)

    # Terminal-only side effects: position + label render on the pane.
    printf '\033[%d;1H\033[2K\033[?25h%s' "$term_height" "$label" >/dev/tty

    local key=""
    read -rsn1 key

    printf '\033[?25l' >/dev/tty

    [[ "$key" == "y" ]]
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
        echo "  ${NAV_C_DIM}No metadata to restore${NAV_C_NORMAL}"
        sleep 0.3
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

# Restore all dormant sessions
restore_all_dormant_sessions() {
    local dormant_count=0
    local restored=0
    local failed=0

    # Count dormant sessions
    # NB: `((dormant_count++))` returns the OLD value as exit code; for the
    # first increment (0 → 1) that exit is 1, which under `set -e` aborts
    # the function. The `|| true` neutralizes that.
    for id in "${SESSION_IDS[@]:-}"; do
        local state
        state=$(get_session_state "$id")
        if [[ "$state" == "$STATE_DORMANT" ]]; then
            ((dormant_count++)) || true
        fi
    done

    if [[ $dormant_count -eq 0 ]]; then
        echo ""
        echo "  ${NAV_C_DIM}No dormant sessions${NAV_C_NORMAL}"
        sleep 0.5
        return
    fi

    echo ""
    echo "  ${NAV_C_ACCENT}Restoring $dormant_count dormant sessions...${NAV_C_NORMAL}"

    # Restore each dormant session
    for id in "${SESSION_IDS[@]:-}"; do
        local state
        state=$(get_session_state "$id")
        if [[ "$state" == "$STATE_DORMANT" ]]; then
            if "$SCRIPT_DIR/session-restore.sh" "$id" 2>/dev/null; then
                ((restored++)) || true
                echo "  ${NAV_C_ACCENT}✓${NAV_C_NORMAL} ${id#tower_}"
            else
                ((failed++)) || true
                echo "  ${NAV_C_ERROR}✗${NAV_C_NORMAL} ${id#tower_}"
            fi
        fi
    done

    echo ""
    echo "  ${NAV_C_ACCENT}Done:${NAV_C_NORMAL} $restored restored, $failed failed"
    sleep 1
}

# Switch to Tile mode: collapse all active single-window Claude sessions into
# a single size-stable grid (lib/tile.sh), install the exit wiring, and hand
# the client over. prefix+Tab (or detaching) returns to the Navigator.
switch_to_tile() {
    info_log "Switching to Tile mode (join-pane)"

    if ! tile_collapse; then
        echo ""
        echo "  ${NAV_C_DIM}No active sessions to tile${NAV_C_NORMAL}"
        sleep 0.8
        return
    fi

    # Surface any sessions skipped for being multi-window.
    if [[ "${TILE_SKIPPED:-0}" -gt 0 ]]; then
        session_tmux display-message -t "$TOWER_TILE_SESSION" \
            "$TILE_SKIPPED multi-window session(s) skipped" 2>/dev/null || true
    fi

    # Exit wiring, server-side. prefix+Tab is the intentional exit: it must
    # carry the client's tty across the teardown so tile-exit.sh can re-attach
    # the Navigator. detach-client -E does exactly that (same mechanism used to
    # ENTER the tile below) — run-shell -b would run tty-less in the server and
    # the re-attach would fail, dropping the client and quitting tmux.
    # The session server's normal prefix is left intact, so native pane keys
    # (prefix+z zoom, prefix+arrow, prefix+o, prefix+{/}, prefix+q) keep working.
    session_tmux bind-key Tab \
        detach-client -E "exec '$SCRIPT_DIR/tile-exit.sh'" 2>/dev/null || true
    # Safety net: if the client detaches some OTHER way (e.g. prefix+d), just
    # disband the tile to restore sessions — do NOT re-enter the Navigator
    # (there is no client tty to attach). TOWER_TILE_NO_REENTER stops before
    # the re-attach. tile_disband is idempotent, so this never double-tears-down.
    session_tmux set-hook -t "$TOWER_TILE_SESSION" client-detached \
        "run-shell -b 'TOWER_TILE_NO_REENTER=1 $SCRIPT_DIR/tile-exit.sh'" 2>/dev/null || true

    # Hand the Navigator client over to the tile session.
    nav_tmux detach-client \
        -E "TMUX= tmux -L '$TOWER_SESSION_SOCKET' attach-session -t '$TOWER_TILE_SESSION'"
}

# Full attach to selected session
# Uses detach-client -E to seamlessly switch from Navigator to the target session
full_attach() {
    local selected
    selected=$(get_nav_selected)

    if [[ -z "$selected" ]]; then
        return
    fi

    # Check if dormant and restore first
    local state
    state=$(get_session_state "$selected")

    if [[ "$state" == "$STATE_DORMANT" ]]; then
        echo "Restoring session..."
        "$SCRIPT_DIR/session-restore.sh" "$selected" 2>/dev/null || true
        sleep 0.5
        # Re-check state after restore
        state=$(get_session_state "$selected")
    fi

    # Verify session exists on session server
    if ! session_tmux has-session -t "$selected" 2>/dev/null; then
        handle_error "Session not found: ${selected#tower_}"
        return 1
    fi

    info_log "Full attach to session: $selected"

    # Use detach-client -E to seamlessly switch from Navigator server to session server
    # This detaches the client from Navigator and immediately attaches to the target session
    # The Navigator session remains alive in the background for fast re-entry
    nav_tmux detach-client -E "TMUX= tmux -L '$TOWER_SESSION_SOCKET' attach-session -t '$selected'"
}

# Invoke session-add.sh for the chosen path. Shared by the picker
# (Enter from the picker) and the manual entry flow.
_create_session_for_path() {
    local path="$1"

    # Expand ~ relative to $HOME
    # shellcheck disable=SC2086
    path="${path/#\~/$HOME}"

    echo ""
    echo "  ${NAV_C_ACCENT}Creating session for: $path${NAV_C_NORMAL}"

    # --no-attach is critical here: session-add.sh's default behaviour is to
    # attach the calling pane to the new tower_* session, which from inside
    # Navigator's list pane would hijack the pane with the new claude
    # process. We just want the metadata + session created; the user picks
    # it up via the normal list flow.
    if "$SCRIPT_DIR/session-add.sh" "$path" --no-attach 2>&1 | tail -3; then
        sleep 0.5
    else
        echo "  ${NAV_C_ERROR}✗ Failed to create session${NAV_C_NORMAL}"
        sleep 1
    fi
}

# Inline path-entry fallback used when the picker is empty or the user
# explicitly switches to manual mode with `m`.
_add_session_manual_entry() {
    local default_path
    default_path=$(_load_caller_cwd)

    local path
    path=$(_prompt_inline "New session path: " "$default_path")
    [[ -z "$path" ]] && return 0
    _create_session_for_path "$path"
}

# Render the Claude-project picker. Returns the chosen index on stdout,
# or one of the sentinel strings:
#   "MANUAL"  user asked to enter a path manually
#   "CANCEL"  user cancelled
#
# Arguments:
#   $1 - selected index (0-based)
#   $2 - newline-separated list of project paths
_render_project_picker() {
    local selected_index="$1"
    local projects="$2"

    local term_height
    term_height=$(tput lines 2>/dev/null || echo 24)
    local max_lines=$((term_height - 6))

    local output=""
    output+="${NAV_C_HEADER}New session — pick a Claude project${NAV_C_NORMAL}\n"
    output+="${NAV_C_DIM}(reads ~/.claude/projects + history.jsonl)${NAV_C_NORMAL}\n"
    output+="\n"

    local i=0
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if ((i >= max_lines)); then
            output+="${NAV_C_DIM}... (more not shown)${NAV_C_NORMAL}\n"
            break
        fi
        if ((i == selected_index)); then
            output+="${NAV_C_SELECTED} ${line} ${NAV_C_NORMAL}\n"
        else
            output+=" ${line}\n"
        fi
        ((i++)) || true
    done <<<"$projects"

    output+="\n"
    output+="${NAV_C_DIM}j/k:nav  Enter:add  m:manual path  q/Esc:cancel${NAV_C_NORMAL}\n"

    local clear_eos
    clear_eos=$(tput ed 2>/dev/null || printf '\033[J')

    # Write to /dev/tty so the render reaches the pane even when the
    # caller wraps us in command substitution (which captures stdout).
    # The selection result still goes to stdout from _run_project_picker.
    printf '\033[?25l\033[H%b%s\033[?25h' "$output" "$clear_eos" >/dev/tty
}

# Main picker loop. Returns:
#   the chosen path on stdout (Enter)
#   ""           cancel
#   "MANUAL"     fallback to manual entry
_run_project_picker() {
    local projects="$1"
    local count
    count=$(grep -c '' <<<"$projects")

    local selected_index=0
    local key
    while true; do
        _render_project_picker "$selected_index" "$projects"

        if IFS= read -rsn1 key; then
            case "$key" in
                j | $'\x1b')
                    if [[ "$key" == $'\x1b' ]]; then
                        local arrow=""
                        read -rsn2 -t 0.1 arrow || true
                        case "$arrow" in
                            '[B') key="j" ;;
                            '[A') key="k" ;;
                            *)
                                echo ""
                                return 0
                                ;; # plain Esc cancels
                        esac
                    fi
                    if [[ "$key" == "j" ]] && ((selected_index < count - 1)); then
                        ((selected_index++))
                    fi
                    ;;
                k)
                    if ((selected_index > 0)); then
                        ((selected_index--))
                    fi
                    ;;
                g)
                    selected_index=0
                    ;;
                G)
                    selected_index=$((count - 1))
                    ;;
                m | M)
                    echo "MANUAL"
                    return 0
                    ;;
                q | Q)
                    echo ""
                    return 0
                    ;;
                '') # Enter
                    sed -n "$((selected_index + 1))p" <<<"$projects"
                    return 0
                    ;;
            esac
        fi
    done
}

# Add a new session — first try the picker, fall back to manual entry
# if Claude has no recorded projects (or all of them are already
# registered as tower sessions).
add_new_session() {
    local projects
    projects=$(_load_claude_projects)

    if [[ -z "$projects" ]]; then
        _add_session_manual_entry
        return
    fi

    local choice
    choice=$(_run_project_picker "$projects")

    case "$choice" in
        "") return 0 ;; # cancelled
        MANUAL) _add_session_manual_entry ;;
        *) _create_session_for_path "$choice" ;;
    esac
}

# Delete the currently selected session after inline y/N confirmation.
# Uses session-delete.sh -f after the user confirms.
delete_selected_session() {
    local selected
    selected=$(get_nav_selected)

    if [[ -z "$selected" ]]; then
        return 0
    fi

    local name="${selected#tower_}"
    if _prompt_yesno_inline "Delete '${name}'? [y/N] "; then
        echo ""
        echo "  ${NAV_C_ACCENT}Deleting: $name${NAV_C_NORMAL}"

        if "$SCRIPT_DIR/session-delete.sh" "$name" -f 2>&1 | tail -2; then
            set_nav_selected ""
            sleep 0.3
        else
            echo "  ${NAV_C_ERROR}✗ Failed to delete${NAV_C_NORMAL}"
            sleep 1
        fi
    fi
}

# Jump selection to the Nth session (1-indexed). No-op if N exceeds the
# session count. Returns the new index on stdout (or the original if no-op).
jump_to_index() {
    local digit="$1"
    local current_index="$2"
    local target=$((digit - 1))

    if ((target < 0 || target >= ${#SESSION_IDS[@]})); then
        echo "$current_index"
        return
    fi

    set_nav_selected "${SESSION_IDS[$target]}"
    signal_view_update
    echo "$target"
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
            target_socket="" # default server
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
            [[ "$id" == "$current_selected" ]] && {
                found=1
                break
            }
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

        # Wait for input with timeout
        local key=""
        # IFS= preserves Tab/space (default IFS would strip them, making
        # Tab indistinguishable from Enter).
        if IFS= read -rsn1 -t "$REFRESH_INTERVAL" key; then
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
                '') # Enter key
                    full_attach
                    ;;
                i)
                    focus_view
                    ;;
                r)
                    # Restore selected dormant session
                    restore_selected
                    build_session_list
                    selected_index=$(get_selection_index)
                    clear
                    ;;
                R)
                    # Restore all dormant sessions
                    restore_all_dormant_sessions
                    build_session_list
                    selected_index=$(get_selection_index)
                    clear
                    ;;
                n)
                    # Create new session via inline prompt
                    add_new_session
                    build_session_list
                    selected_index=$(get_selection_index)
                    clear
                    ;;
                d)
                    # Delete selected session after y/N confirmation
                    delete_selected_session
                    build_session_list
                    selected_index=$(get_selection_index)
                    clear
                    ;;
                [1-9])
                    # Direct jump to Nth session (1-indexed); no-op if N exceeds count
                    selected_index=$(jump_to_index "$key" "$selected_index")
                    ;;
                $'\t') # Tab key
                    switch_to_tile
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
            # Timeout - refresh session list
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

# Only enter the main loop when this script is executed directly, not when
# it is sourced (e.g. by tests that want to call the action functions in
# isolation).
if [[ "${BASH_SOURCE[0]}" == "$0" || -z "${BASH_SOURCE[0]:-}" ]]; then
    main_loop
fi
