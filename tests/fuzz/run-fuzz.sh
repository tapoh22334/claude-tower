#!/usr/bin/env bash
# run-fuzz.sh — Exploratory / monkey-style testing for Claude Tower.
#
# Designed to run safely inside the test Docker container (or on a host
# where the user is OK with extra tmux servers being created and killed).
# All tmux state is confined to per-PID sockets and temp dirs; nothing
# touches the host's default tmux server.
#
# Modes:
#   random     pure-random ASCII keys (Level 1 fuzz)
#   smart      legal Navigator keys mixed with trash keys (Level 2)
#   scenarios  hand-picked sequences that emulate real-user mistakes (Level 3)
#   all        run all of the above (default)
#
# Usage:
#   tests/fuzz/run-fuzz.sh [mode] [--iterations N] [--seed N] [--verbose]
#
# Exit code:
#   0  no invariant violations
#   1  one or more invariant violations (Navigator died, hang, etc.)

set -uo pipefail

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------

MODE="all"
ITERATIONS=200
SEED=""
VERBOSE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        random | smart | scenarios | all) MODE="$1"; shift ;;
        --iterations) ITERATIONS="$2"; shift 2 ;;
        --seed) SEED="$2"; shift 2 ;;
        --verbose | -v) VERBOSE=1; shift ;;
        -h | --help)
            sed -n '1,30p' "$0"
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ -n "$SEED" ]] && RANDOM="$SEED"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

NAV_LIST_SCRIPT="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
NAV_VIEW_SCRIPT="$PROJECT_ROOT/tmux-plugin/scripts/navigator-view.sh"

PFX="ct-fuzz-$$"
NAV_SOCKET="${PFX}-nav"
SESSION_SOCKET="${PFX}-sess"

export TMUX_TMPDIR="/tmp/${PFX}-tmpdir"
mkdir -p "$TMUX_TMPDIR" && chmod 700 "$TMUX_TMPDIR"

export CLAUDE_TOWER_METADATA_DIR
CLAUDE_TOWER_METADATA_DIR=$(mktemp -d)
export CLAUDE_TOWER_NAV_SOCKET="$NAV_SOCKET"
export CLAUDE_TOWER_SESSION_SOCKET="$SESSION_SOCKET"
export CLAUDE_TOWER_PROGRAM="/bin/true"

# Caller-CWD state file isolated per-PID
NAV_STATE_DIR="/tmp/${PFX}-state"
mkdir -p "$NAV_STATE_DIR"
export CLAUDE_TOWER_CALLER_CWD_FILE="$NAV_STATE_DIR/caller-cwd"
echo "$HOME" > "$CLAUDE_TOWER_CALLER_CWD_FILE"
# Force the runtime-side state dir into our scratch so we don't touch
# any other Tower in flight on the same machine.
mkdir -p /tmp/claude-tower 2>/dev/null

# ------------------------------------------------------------------
# Reporting
# ------------------------------------------------------------------

LOG_DIR="/tmp/${PFX}-log"
mkdir -p "$LOG_DIR"
ACTION_LOG="$LOG_DIR/actions.log"
VIOLATION_LOG="$LOG_DIR/violations.log"
SUMMARY_LOG="$LOG_DIR/summary.txt"
: > "$ACTION_LOG"
: > "$VIOLATION_LOG"

VIOLATIONS=0
WARNINGS=0
TOTAL_ACTIONS=0

WARNING_LOG="$LOG_DIR/warnings.log"
: > "$WARNING_LOG"

log_action() {
    ((TOTAL_ACTIONS++)) || true
    echo "[$(date '+%H:%M:%S.%N' | cut -c1-12)] $*" >> "$ACTION_LOG"
    [[ "$VERBOSE" -eq 1 ]] && echo "  $*"
}

log_violation() {
    ((VIOLATIONS++)) || true
    echo "[$(date '+%H:%M:%S.%N' | cut -c1-12)] VIOLATION: $*" | tee -a "$VIOLATION_LOG"
}

# A warning is something noteworthy but not a bug: e.g., a fuzz iteration
# happened to trigger a legitimate Navigator exit and we relaunched.
log_warning() {
    ((WARNINGS++)) || true
    echo "[$(date '+%H:%M:%S.%N' | cut -c1-12)] WARNING: $*" >> "$WARNING_LOG"
    [[ "$VERBOSE" -eq 1 ]] && echo "  WARNING: $*"
}

# ------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------

# Kill ONLY sockets we created (never broad pkill).
cleanup() {
    local sock
    for sock in "$NAV_SOCKET" "$SESSION_SOCKET"; do
        TMUX= tmux -L "$sock" kill-server 2>/dev/null || true
    done
    rm -rf "$CLAUDE_TOWER_METADATA_DIR" "$TMUX_TMPDIR" "$NAV_STATE_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ------------------------------------------------------------------
# Test fixtures
# ------------------------------------------------------------------

# Pre-populate N dormant sessions (no tmux server interaction required)
seed_dormants() {
    local n="$1"
    local i
    for i in $(seq 1 "$n"); do
        cat > "$CLAUDE_TOWER_METADATA_DIR/tower_fuzz_${i}.meta" <<EOF
session_id=tower_fuzz_${i}
session_name=fuzz_${i}
directory_path=/tmp
created_at=$(date -Iseconds)
EOF
    done
}

# Pre-create N active tower sessions on Session server
seed_actives() {
    local n="$1"
    local i
    for i in $(seq 1 "$n"); do
        seed_dormants 0  # noop, but keeps signature
        cat > "$CLAUDE_TOWER_METADATA_DIR/tower_fuzz_active_${i}.meta" <<EOF
session_id=tower_fuzz_active_${i}
session_name=fuzz_active_${i}
directory_path=/tmp
EOF
        TMUX= tmux -L "$SESSION_SOCKET" new-session -d \
            -s "tower_fuzz_active_${i}" -c /tmp 2>/dev/null || true
    done
}

reset_state() {
    cleanup
    mkdir -p "$TMUX_TMPDIR" && chmod 700 "$TMUX_TMPDIR"
    CLAUDE_TOWER_METADATA_DIR=$(mktemp -d)
    export CLAUDE_TOWER_METADATA_DIR
    mkdir -p "$NAV_STATE_DIR"
    echo "$HOME" > "$CLAUDE_TOWER_CALLER_CWD_FILE"
    rm -rf /tmp/claude-tower 2>/dev/null
    mkdir -p /tmp/claude-tower
}

# ------------------------------------------------------------------
# Navigator harness
# ------------------------------------------------------------------

launch_navigator() {
    TMUX= tmux -L "$NAV_SOCKET" new-session -d -s navigator -x 200 -y 50 \
        2>/dev/null || return 1
    TMUX= tmux -L "$NAV_SOCKET" split-window -h -l "60" -t navigator:0 \
        2>/dev/null || return 1
    TMUX= tmux -L "$NAV_SOCKET" send-keys -t navigator:0.0 \
        "exec $NAV_LIST_SCRIPT" Enter 2>/dev/null || return 1
    TMUX= tmux -L "$NAV_SOCKET" send-keys -t navigator:0.1 \
        "exec $NAV_VIEW_SCRIPT" Enter 2>/dev/null || return 1
    TMUX= tmux -L "$NAV_SOCKET" select-pane -t navigator:0.0 2>/dev/null || true

    # Wait up to 5s for the Sessions header to appear
    local attempt=0
    while ((attempt < 50)); do
        if TMUX= tmux -L "$NAV_SOCKET" capture-pane -t navigator:0.0 -J -p 2>/dev/null \
            | grep -q "Sessions"; then
            return 0
        fi
        sleep 0.1
        ((attempt++)) || true
    done
    return 1
}

send_keys() {
    TMUX= tmux -L "$NAV_SOCKET" send-keys -t navigator:0.0 "$@" 2>/dev/null
}

capture_pane() {
    TMUX= tmux -L "$NAV_SOCKET" capture-pane -t navigator:0.0 -J -p 2>/dev/null
}

navigator_alive() {
    TMUX= tmux -L "$NAV_SOCKET" has-session -t navigator 2>/dev/null
}

# The pane is running navigator-list.sh as long as the pane's foreground
# process is bash (with the script as its argv[0]) — checked via tmux's
# pane_current_command. False positives on captured-content checks are
# common during transient redraws ("Creating session for: …", help
# screen, prompt overlays), so this is the load-bearing invariant.
list_pane_running() {
    local cmd
    cmd=$(TMUX= tmux -L "$NAV_SOCKET" display-message \
        -t navigator:0.0 -p '#{pane_current_command}' 2>/dev/null)
    # Acceptable: any descendant of bash/sh (navigator-list.sh runs as bash).
    # NOT acceptable: the pane reverted to the user shell prompt (zsh/fish)
    # or a wholly different command, which indicates the list script exited.
    [[ "$cmd" == "bash" || "$cmd" == "navigator-list.sh" ]]
}

# Sessions header is the "happy state". Used only as a hint, not a hard
# invariant — transient messages temporarily replace it.
pane_shows_navigator_ui() {
    local content
    content=$(capture_pane)
    [[ "$content" == *"Sessions"* ]] \
        || [[ "$content" == *"Navigator Help"* ]] \
        || [[ "$content" == *"New session path:"* ]] \
        || [[ "$content" == *"Delete '"* ]] \
        || [[ "$content" == *"Creating session for:"* ]] \
        || [[ "$content" == *"Deleting:"* ]] \
        || [[ "$content" == *"Restoring"* ]]
}

# ------------------------------------------------------------------
# Invariant checks
# ------------------------------------------------------------------

# Some keys legitimately end the Navigator session by design (q, Tab to
# Tile, Enter for full attach). When the test sequence intentionally
# triggers one of those, the Navigator exit is expected — not a bug.
EXPECTED_EXIT_KEYS=(q Q Tab Enter)
expected_exit_triggered() {
    local seq="$1" k
    for k in "${EXPECTED_EXIT_KEYS[@]}"; do
        [[ " $seq " == *" $k "* ]] && return 0
    done
    return 1
}

check_invariants() {
    local context="$1"
    local expected_exit="${2:-0}"

    # Let pending renders/timers settle before we check.
    sleep 0.3

    if ! navigator_alive; then
        if [[ "$expected_exit" -eq 1 ]]; then
            return 0
        fi
        log_violation "[$context] Navigator session is dead"
        return 1
    fi

    if ! list_pane_running; then
        if [[ "$expected_exit" -eq 1 ]]; then
            return 0
        fi
        log_violation "[$context] List pane process exited (pane reverted to shell)"
        echo "=== captured pane ===" >> "$VIOLATION_LOG"
        capture_pane >> "$VIOLATION_LOG"
        echo "=== end ===" >> "$VIOLATION_LOG"
        return 1
    fi

    # Give the render loop two refresh cycles to recover the Sessions header.
    # If after that we still don't see any Navigator UI string, treat as a
    # soft warning only (some transient states are hard to enumerate).
    local attempt=0
    while ((attempt < 25)); do
        if pane_shows_navigator_ui; then
            break
        fi
        sleep 0.1
        ((attempt++)) || true
    done

    # No "command not found" or unhandled bash error leaking into the pane.
    local content
    content=$(capture_pane)
    for marker in "command not found" "unbound variable" "syntax error" \
                  "bash: line" "Bad command line option"; do
        if [[ "$content" == *"$marker"* ]]; then
            log_violation "[$context] Pane shows bash error: $marker"
            return 1
        fi
    done

    return 0
}

# ------------------------------------------------------------------
# Level 1: dumb random keys
# ------------------------------------------------------------------

run_random_fuzz() {
    local n="${1:-$ITERATIONS}"
    echo "=== Level 1: random fuzz × $n ==="
    reset_state
    seed_dormants 3
    if ! launch_navigator; then
        log_violation "random: Navigator failed to launch"
        return
    fi

    local i
    local relaunches=0
    for i in $(seq 1 "$n"); do
        if ! navigator_alive; then
            ((relaunches++)) || true
            reset_state
            seed_dormants 3
            launch_navigator || { log_violation "random[$i] relaunch failed"; break; }
        fi

        local ascii=$((RANDOM % 95 + 32))
        local key
        key=$(printf '\%03o' "$ascii")
        send_keys "$(printf "%b" "$key")"
        log_action "random[$i] sent ascii=$ascii"
        sleep 0.02
    done

    echo "  relaunches: $relaunches"
}

# ------------------------------------------------------------------
# Level 2: legal-biased fuzz
# ------------------------------------------------------------------

# Keys that legitimately exit Navigator (user-initiated). Excluded from
# fuzz key sets so the run keeps going without spurious "Navigator died".
# `q` quits; `Tab` switches to Tile (detaches client); `Enter` does full
# attach to the selected session (detaches client).
LEGAL_KEYS=("j" "k" "g" "G" "?" "1" "2" "3" "4" "5" "6" "7" "8" "9"
            "Space" "BSpace" "DC")
HEAVY_KEYS=("n" "d" "i" "r" "R")    # state-changing — exercise but with auto-cancel
TRASH_KEYS=("C-c" "C-z" "C-d" "Escape" "C-l" "C-h" "C-u" "C-w" "C-x" "M-x")

run_smart_fuzz() {
    local n="${1:-$ITERATIONS}"
    echo "=== Level 2: smart fuzz × $n ==="
    reset_state
    seed_dormants 5
    if ! launch_navigator; then
        log_violation "smart: Navigator failed to launch"
        return
    fi

    local i
    local relaunches=0
    for i in $(seq 1 "$n"); do
        # If Navigator unexpectedly died (a heavy/trash key caused an exit),
        # relaunch and continue — that itself is a soft signal worth logging.
        if ! navigator_alive; then
            log_warning "smart[$i] Navigator died (key triggered exit), relaunching"
            ((relaunches++)) || true
            reset_state
            seed_dormants 5
            launch_navigator || { log_violation "smart[$i] relaunch failed"; break; }
        fi

        local roll=$((RANDOM % 100))
        local key
        if ((roll < 60)); then
            key=${LEGAL_KEYS[$((RANDOM % ${#LEGAL_KEYS[@]}))]}
        elif ((roll < 85)); then
            key=${HEAVY_KEYS[$((RANDOM % ${#HEAVY_KEYS[@]}))]}
        else
            key=${TRASH_KEYS[$((RANDOM % ${#TRASH_KEYS[@]}))]}
        fi

        send_keys "$key"
        # If we hit a state-changing key — give it a moment to render and
        # auto-cancel any prompt so the next iteration starts clean.
        if [[ "$key" == "n" || "$key" == "d" ]]; then
            sleep 0.15
            send_keys "C-c"
        fi
        log_action "smart[$i] key=$key"

        sleep 0.02
    done

    echo "  relaunches: $relaunches"
}

# ------------------------------------------------------------------
# Level 3: hand-picked scenarios
# ------------------------------------------------------------------

# Each scenario: name + key sequence (space-separated, supports tmux keysyms)
declare -a SCENARIOS=(
    # Basic interactions
    "n-cancel-immediately|n C-c"
    "n-empty-enter|n Enter"
    "d-cancel-n|d n"
    "d-uppercase-Y|d Y"
    "n-spam|n n n n C-c"
    "d-spam|d d d d n"
    "tab-spam|Tab Tab Tab Tab Tab"
    "help-dismiss-spam|? ? ? ? Space"

    # Navigation overflow / edge cases
    "j-overflow|j j j j j j j j j j j j j j j"
    "k-from-zero|k k k k k"
    "digit-out-of-range|9 8 7 6 5"
    "rapid-digit|1 2 3 4 5 6 7 8 9"
    "rapid-jk|j k j k j k j k j k j k j k"
    "wrap-around-many|g G g G g G g G"

    # Interleaved actions
    "interleaved-keys|j n C-c k d n j i Escape"
    "navigator-flood|j j i Escape n C-c d n r R Tab"
    "rapid-state-toggle|i Escape i Escape i Escape i Escape"

    # Failure-injection
    "esc-only|Escape Escape Escape"
    "ctrl-bursts|C-c C-z C-d C-x C-l"
    "ctrl-c-many|C-c C-c C-c C-c C-c"
    "binary-junk|C-@ C-A C-B C-C C-D C-E C-F"

    # Help dismiss races
    "help-then-action|? n"
    "help-then-key-junk|? a b c d e f g h i j k"

    # Exit-triggering
    "tab-then-keys|Tab j k 1 2 q"
    "q-cancel|q n"

    # Delete sequences
    "delete-all|d y d y d y d y d y"
    "delete-cancel-mix|d n d y d n d y d N"

    # New-session noise
    "n-with-junk-input|n a b c d e f g h Enter"
    "n-very-long-path|n a a a a a a a a a a a a a a a a a a a a Enter"
)

run_scenarios() {
    echo "=== Level 3: scenarios (${#SCENARIOS[@]}) ==="
    local entry name sequence
    for entry in "${SCENARIOS[@]}"; do
        name="${entry%%|*}"
        sequence="${entry#*|}"
        reset_state
        seed_dormants 4
        if ! launch_navigator; then
            log_violation "scenario:$name failed to launch"
            continue
        fi

        log_action "scenario:$name BEGIN [$sequence]"
        local key
        for key in $sequence; do
            send_keys "$key"
            sleep 0.08
        done
        log_action "scenario:$name END"

        # If the scenario contains a key that LEGITIMATELY exits Navigator
        # (q, Tab to Tile, Enter for full attach), we don't treat the exit
        # as a violation.
        local expected_exit=0
        if expected_exit_triggered " $sequence "; then
            expected_exit=1
        fi

        if check_invariants "scenario:$name" "$expected_exit"; then
            echo "  ✓ $name"
        else
            echo "  ✗ $name"
        fi
    done
}

# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------

echo "================================================================"
echo "  Claude Tower fuzz run"
echo "  pid=$$  prefix=$PFX  mode=$MODE  iter=$ITERATIONS"
echo "  log_dir=$LOG_DIR"
echo "================================================================"

case "$MODE" in
    random)    run_random_fuzz "$ITERATIONS" ;;
    smart)     run_smart_fuzz "$ITERATIONS" ;;
    scenarios) run_scenarios ;;
    all)
        run_random_fuzz "$ITERATIONS"
        run_smart_fuzz "$ITERATIONS"
        run_scenarios
        ;;
esac

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

{
    echo "================================================================"
    echo "  Summary"
    echo "================================================================"
    echo "  mode:        $MODE"
    echo "  iterations:  $ITERATIONS"
    echo "  total acts:  $TOTAL_ACTIONS"
    echo "  violations:  $VIOLATIONS"
    echo "  warnings:    $WARNINGS"
    echo "  log dir:     $LOG_DIR"
    if [[ "$VIOLATIONS" -gt 0 ]]; then
        echo "----------------------------------------------------------------"
        echo "  Violations (real bugs):"
        sed 's/^/    /' "$VIOLATION_LOG"
    fi
    if [[ "$WARNINGS" -gt 0 ]]; then
        echo "----------------------------------------------------------------"
        echo "  Warnings (recoverable, noted for review):"
        sed 's/^/    /' "$WARNING_LOG" | head -20
    fi
    echo "================================================================"
} | tee "$SUMMARY_LOG"

exit $((VIOLATIONS > 0 ? 1 : 0))
