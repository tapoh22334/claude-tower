# Tile View join-pane Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Tile View's fragile nested-attach mirror (which shrinks panes 1 row per redraw) with native `join-pane` relocation so the grid is size-stable, while preserving each Claude session's identity and exiting cleanly back to the Navigator.

**Architecture:** All active `tower_*` sessions' Claude panes are moved (via `join-pane`) into one dedicated `tower-tile` session's window — a single client, so no size negotiation and no recursion. Each source session keeps a resident `_tile_holder` window so it is never destroyed. A pane option `@tower_name` plus an atomic map file (`/tmp/claude-tower/tile.map`) record identity for teardown. Exit (`prefix+Tab` or client-detach) disbands the tile, returns each pane to its session, and re-enters the Navigator. `prefix+t` keeps its global "leave Tower" meaning.

**Tech Stack:** Bash 4+, tmux 3.2+ (validated on 3.6a), bats (Bash Automated Testing System), shellcheck/shfmt.

**Design doc:** `docs/superpowers/specs/2026-06-08-tile-join-pane-redesign-design.md`

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `tmux-plugin/lib/tile.sh` | Shared tile state machine: `tile_collapse` (enter) and `tile_disband` (exit/sweep). Sourced by `navigator-list.sh` and `tile-exit.sh`. | **Create** |
| `tmux-plugin/scripts/tile-exit.sh` | Server-side entry point invoked by `prefix+Tab` / `client-detached`: capture focus, disband, re-enter Navigator. | **Create** |
| `tmux-plugin/scripts/navigator-list.sh` | `switch_to_tile` becomes a thin wrapper around `tile_collapse`; the `Tab` handler is unchanged. | **Modify** (`switch_to_tile` ~577-663) |
| `tmux-plugin/lib/common.sh` | Add `TOWER_TILE_*` constants and `set_nav_warning` / `get_nav_warning` helpers. | **Modify** |
| `tmux-plugin/claude-tower.tmux` | Startup orphan sweep for stray `_tile_holder` / `tower-tile`. | **Modify** |
| `tmux-plugin/conf/tile-pane.conf` | Nested-attach config — obsolete. | **Delete** |
| `tests/integration/test_tile_join_pane.bats` | New behavioural tests for `tile_collapse` / `tile_disband` (the bulk of coverage). | **Create** |
| `tests/integration/test_navigator_new_keys.bats` | Remove old tile-pane.conf / split-window assertions; add join-pane source assertions. | **Modify** (~95-120) |
| `tests/e2e/test_navigator_uie2e.bats` | Remove 6 old nested-attach tile tests; add a Tab→collapse smoke test. | **Modify** (~513-637) |

**Why a separate `lib/tile.sh`:** the enter and exit logic share the map-file
format, the `@tower_name` convention, and the `tile_disband` function (ENTER's
sweep reuses it). Keeping it in one sourceable file means one implementation and
makes it directly unit-testable without driving a real client.

---

## Conventions used throughout

- `session_tmux ...` is the existing helper in `common.sh` = `TMUX= tmux -L "$TOWER_SESSION_SOCKET" ...`. All tile state lives on the **session server**.
- Tests use `/bin/sleep 600` as the Claude stand-in so panes have a stable, trackable PID. Set `CLAUDE_TOWER_SESSION_SOCKET` / `TMUX_TMPDIR` **before** sourcing.
- New constants: `TOWER_TILE_SESSION="tower-tile"`, `TOWER_TILE_HOLDER_WINDOW="_tile_holder"`, `TOWER_TILE_MAP_FILE="${TOWER_NAV_STATE_DIR}/tile.map"`.

---

## Task 1: Add tile constants and warning helpers to common.sh

**Files:**
- Modify: `tmux-plugin/lib/common.sh` (after line 149, the state-file block)

- [ ] **Step 1: Write the failing test**

Create `tests/integration/test_tile_join_pane.bats` with this header and first test:

```bash
#!/usr/bin/env bats
# Behavioural tests for the join-pane Tile View (lib/tile.sh).
# Each Claude session is stood in by `/bin/sleep 600` so panes have a
# stable PID we can track across the collapse/disband round trip.

PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SESSION_SOCKET="ct-tile-sess-$$"

setup() {
    export TMUX_TMPDIR="/tmp/ct-tile-$$"
    mkdir -p "$TMUX_TMPDIR"; chmod 700 "$TMUX_TMPDIR"
    export CLAUDE_TOWER_SESSION_SOCKET="$SESSION_SOCKET"
    export TOWER_NAV_STATE_DIR_OVERRIDE="/tmp/ct-tile-state-$$"
    rm -rf "$TOWER_NAV_STATE_DIR_OVERRIDE"; mkdir -p "$TOWER_NAV_STATE_DIR_OVERRIDE"

    # common.sh sets strict mode + an ERR trap that, under bats, can spiral
    # on a failing assertion. Source defensively and drop the trap — this
    # mirrors tests/integration/test_return_to_caller.bats.
    set +euo pipefail
    # shellcheck disable=SC1090,SC1091
    source "$PROJECT_ROOT/tmux-plugin/lib/common.sh"
    source "$PROJECT_ROOT/tmux-plugin/lib/tile.sh"
    set -euo pipefail
    trap - ERR

    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
}

teardown() {
    TMUX= tmux -L "$SESSION_SOCKET" kill-server 2>/dev/null || true
    rm -rf "$TMUX_TMPDIR" "$TOWER_NAV_STATE_DIR_OVERRIDE" 2>/dev/null || true
}

# Make an active Claude session: one window named `claude` running sleep.
make_claude() {
    local name="$1"
    TMUX= tmux -L "$SESSION_SOCKET" new-session -d -s "tower_${name}" \
        -n claude -x 200 -y 50 "exec /bin/sleep 600"
}

@test "tile: constants are defined" {
    [ "$TOWER_TILE_SESSION" = "tower-tile" ]
    [ "$TOWER_TILE_HOLDER_WINDOW" = "_tile_holder" ]
    [ -n "$TOWER_TILE_MAP_FILE" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/bats/bin/bats tests/integration/test_tile_join_pane.bats -f "constants"`
Expected: FAIL — `lib/tile.sh` does not exist (source error) and constants unset.

- [ ] **Step 3: Add the constants and helpers to common.sh**

In `tmux-plugin/lib/common.sh`, immediately after line 149 (`readonly TOWER_VIEW_UPDATE_CHANNEL=...`), add:

```bash
# ----------------------------------------------------------------------------
# Tile View (join-pane) constants and state
# ----------------------------------------------------------------------------

# Dedicated session that hosts the tile grid (all Claude panes joined here).
readonly TOWER_TILE_SESSION="tower-tile"

# Per-session placeholder window that keeps a tower_X alive while its Claude
# pane is on loan to the tile grid. Leading underscore marks it internal.
readonly TOWER_TILE_HOLDER_WINDOW="_tile_holder"

# Map file: lines of "<pane_id>\t<session_name>", the teardown source of truth.
# Test override lets the bats suite isolate state.
readonly TOWER_TILE_MAP_FILE="${TOWER_NAV_STATE_DIR_OVERRIDE:-$TOWER_NAV_STATE_DIR}/tile.map"

# Warning breadcrumb the Navigator renders on its next draw.
readonly TOWER_NAV_WARNING_FILE="${TOWER_NAV_STATE_DIR_OVERRIDE:-$TOWER_NAV_STATE_DIR}/warning"

# Record a one-line warning for the Navigator to surface to the user.
set_nav_warning() {
    mkdir -p "$(dirname "$TOWER_NAV_WARNING_FILE")" 2>/dev/null || true
    printf '%s\n' "$1" >"$TOWER_NAV_WARNING_FILE" 2>/dev/null || true
}

# Read and clear the pending Navigator warning (empty if none).
get_nav_warning() {
    if [[ -f "$TOWER_NAV_WARNING_FILE" ]]; then
        cat "$TOWER_NAV_WARNING_FILE" 2>/dev/null || true
        rm -f "$TOWER_NAV_WARNING_FILE" 2>/dev/null || true
    fi
}
```

Note: `TOWER_NAV_STATE_DIR_OVERRIDE` is honoured only for these two paths so tests can redirect them; production leaves it unset and uses `TOWER_NAV_STATE_DIR`.

- [ ] **Step 4: Create a stub `lib/tile.sh` so the source succeeds**

Create `tmux-plugin/lib/tile.sh`:

```bash
#!/usr/bin/env bash
# tile.sh - join-pane Tile View state machine (sourced, not executed).
# Provides tile_collapse (enter) and tile_disband (exit/sweep).
# Relies on common.sh being sourced first (session_tmux, TOWER_TILE_*).

# (functions added in later tasks)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `./tests/bats/bin/bats tests/integration/test_tile_join_pane.bats -f "constants"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add tmux-plugin/lib/common.sh tmux-plugin/lib/tile.sh tests/integration/test_tile_join_pane.bats
git commit -m "feat(tile): add join-pane constants and nav-warning helpers"
```

---

## Task 2: Implement `tile_disband` (exit/sweep) — the riskiest path first

We implement teardown before enter because ENTER's idempotency sweep calls it,
and because disband-without-collapse is independently testable by hand-building
a tile state.

**Files:**
- Modify: `tmux-plugin/lib/tile.sh`
- Test: `tests/integration/test_tile_join_pane.bats`

- [ ] **Step 1: Write the failing test**

Append to `tests/integration/test_tile_join_pane.bats`:

```bash
# Hand-build a tile state: collapse one claude pane into tower-tile with a
# holder left behind, write the map, then disband and assert restoration.
@test "tile_disband: restores session by name with same PID" {
    make_claude alpha
    local pid; pid=$(TMUX= tmux -L "$SESSION_SOCKET" \
        list-panes -t tower_alpha:claude -F '#{pane_pid}')
    local pane; pane=$(TMUX= tmux -L "$SESSION_SOCKET" \
        list-panes -t tower_alpha:claude -F '#{pane_id}')

    # Build tile-tile session + holder, then join the claude pane in.
    TMUX= tmux -L "$SESSION_SOCKET" new-session -d -s tower-tile -n tile "exec /bin/sleep 600"
    local tw; tw=$(TMUX= tmux -L "$SESSION_SOCKET" display-message -p -t tower-tile '#{window_id}')
    TMUX= tmux -L "$SESSION_SOCKET" new-window -d -t tower_alpha -n _tile_holder "exec /bin/sleep 600"
    TMUX= tmux -L "$SESSION_SOCKET" set-option -p -t "$pane" @tower_name tower_alpha
    printf '%s\t%s\n' "$pane" tower_alpha >"$TOWER_TILE_MAP_FILE"
    TMUX= tmux -L "$SESSION_SOCKET" join-pane -s "$pane" -t "$tw"

    run tile_disband
    [ "$status" -eq 0 ]

    # tower_alpha restored, single window named claude, same PID, no holder.
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_alpha
    local wc; wc=$(TMUX= tmux -L "$SESSION_SOCKET" list-windows -t tower_alpha | wc -l)
    [ "$wc" -eq 1 ]
    local newpid; newpid=$(TMUX= tmux -L "$SESSION_SOCKET" \
        list-panes -t tower_alpha -F '#{pane_pid}')
    [ "$newpid" = "$pid" ]
    ! TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower-tile
    [ ! -f "$TOWER_TILE_MAP_FILE" ]
}

@test "tile_disband: skips a crashed pane and warns (non-zero)" {
    make_claude beta
    local pane; pane=$(TMUX= tmux -L "$SESSION_SOCKET" \
        list-panes -t tower_beta:claude -F '#{pane_id}')
    # Map references a pane id that does not exist (simulated crash).
    printf '%s\t%s\n' "%999" tower_beta >"$TOWER_TILE_MAP_FILE"

    run tile_disband
    [ "$status" -eq 1 ]                 # anomaly reported
    [ ! -f "$TOWER_TILE_MAP_FILE" ]     # map still cleared
}

@test "tile_disband: no map file is a clean no-op" {
    run tile_disband
    [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/bats/bin/bats tests/integration/test_tile_join_pane.bats -f "tile_disband"`
Expected: FAIL — `tile_disband: command not found`.

- [ ] **Step 3: Implement `tile_disband` in `lib/tile.sh`**

Append to `tmux-plugin/lib/tile.sh`:

```bash
# tile_disband — return every mapped pane to its tower_X session and tear the
# tile down. Idempotent and crash-safe. Returns 0 if clean, 1 on any anomaly
# (so callers can surface a warning). Pure state repair: attaches nothing.
tile_disband() {
    [[ -f "$TOWER_TILE_MAP_FILE" ]] || return 0
    local rc=0 pane sess holder ph
    while IFS=$'\t' read -r pane sess; do
        [[ -n "$pane" && -n "$sess" ]] || continue
        if ! session_tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane"; then
            error_log "tile: pane $pane ($sess) gone (Claude exited); skipping"
            rc=1
            continue
        fi
        holder="${sess}:${TOWER_TILE_HOLDER_WINDOW}"
        if session_tmux has-session -t "$sess" 2>/dev/null; then
            # Happy path: holder kept the session alive — join the pane back.
            if session_tmux join-pane -s "$pane" -t "$holder" 2>/dev/null; then
                session_tmux kill-window -t "$holder" 2>/dev/null || true
                session_tmux rename-window -t "${sess}:" claude 2>/dev/null || true
            else
                error_log "tile: failed to rejoin $pane into $sess"
                rc=1
            fi
        else
            # Session vanished entirely — recreate it from the surviving pane.
            if session_tmux new-session -d -s "$sess" -n claude 2>/dev/null; then
                ph=$(session_tmux list-panes -t "${sess}:" -F '#{pane_id}' | head -1)
                session_tmux join-pane -s "$pane" -t "${sess}:" 2>/dev/null || rc=1
                session_tmux kill-pane -t "$ph" 2>/dev/null || true
            else
                error_log "tile: failed to recreate session $sess"
                rc=1
            fi
        fi
    done <"$TOWER_TILE_MAP_FILE"
    rm -f "$TOWER_TILE_MAP_FILE"
    session_tmux has-session -t "$TOWER_TILE_SESSION" 2>/dev/null &&
        session_tmux kill-session -t "$TOWER_TILE_SESSION" 2>/dev/null || true
    return "$rc"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/bats/bin/bats tests/integration/test_tile_join_pane.bats -f "tile_disband"`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add tmux-plugin/lib/tile.sh tests/integration/test_tile_join_pane.bats
git commit -m "feat(tile): implement crash-safe tile_disband teardown"
```

---

## Task 3: Implement `tile_collapse` (enter)

**Files:**
- Modify: `tmux-plugin/lib/tile.sh`
- Test: `tests/integration/test_tile_join_pane.bats`

- [ ] **Step 1: Write the failing test**

Append:

```bash
@test "tile_collapse: collapses N sessions into tower-tile, panes tagged" {
    make_claude one; make_claude two; make_claude three
    run tile_collapse
    [ "$status" -eq 0 ]

    # tower-tile exists with one pane per session.
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower-tile
    local pc; pc=$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower-tile | wc -l)
    [ "$pc" -eq 3 ]

    # Each pane carries @tower_name; map file matches.
    local tags; tags=$(TMUX= tmux -L "$SESSION_SOCKET" \
        list-panes -t tower-tile -F '#{@tower_name}' | sort | tr '\n' ' ')
    [ "$tags" = "tower_one tower_three tower_two " ]
    [ "$(wc -l <"$TOWER_TILE_MAP_FILE")" -eq 3 ]

    # Each source session is still alive (held by _tile_holder).
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_one
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_two
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_three
}

@test "tile_collapse: round-trips back to standalone sessions, same PIDs" {
    make_claude a; make_claude b
    local pa; pa=$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower_a:claude -F '#{pane_pid}')
    local pb; pb=$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower_b:claude -F '#{pane_pid}')

    tile_collapse
    tile_disband

    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_a
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_b
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower_a -F '#{pane_pid}')" = "$pa" ]
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower_b -F '#{pane_pid}')" = "$pb" ]
    ! TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower-tile
}

@test "tile_collapse: 5 sessions tile without 'pane too small'" {
    make_claude s1; make_claude s2; make_claude s3; make_claude s4; make_claude s5
    run tile_collapse
    [ "$status" -eq 0 ]
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower-tile | wc -l)" -eq 5 ]
}

@test "tile_collapse: multi-window session is skipped and counted" {
    make_claude solo
    make_claude multi
    TMUX= tmux -L "$SESSION_SOCKET" new-window -d -t tower_multi -n extra "exec /bin/sleep 600"

    run tile_collapse
    [ "$status" -eq 0 ]
    # Only the single-window session is tiled.
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower-tile | wc -l)" -eq 1 ]
    # The skip count is exposed via the global TILE_SKIPPED.
    [ "$TILE_SKIPPED" -eq 1 ]
    # The multi-window session is untouched.
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-windows -t tower_multi | wc -l)" -eq 2 ]
}

@test "tile_collapse: no tileable sessions returns non-zero, builds nothing" {
    run tile_collapse
    [ "$status" -ne 0 ]
    ! TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower-tile
}

@test "tile_collapse: re-entry after interrupted state recovers (idempotent)" {
    make_claude x; make_claude y
    tile_collapse
    # Simulate a fresh ENTER while already tiled: should disband then rebuild.
    run tile_collapse
    [ "$status" -eq 0 ]
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower-tile | wc -l)" -eq 2 ]
    # No stray holders left in the sessions.
    [ "$(TMUX= tmux -L "$SESSION_SOCKET" list-windows -t tower_x | wc -l)" -eq 1 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/bats/bin/bats tests/integration/test_tile_join_pane.bats -f "tile_collapse"`
Expected: FAIL — `tile_collapse: command not found`.

- [ ] **Step 3: Implement `tile_collapse` in `lib/tile.sh`**

Append:

```bash
# TILE_SKIPPED is set by tile_collapse to the count of sessions excluded
# because they had more than one window (Bug 1 guard).
TILE_SKIPPED=0

# tile_collapse — move every single-window active tower_X's claude pane into a
# dedicated tower-tile grid. Idempotent (disbands any prior tile first). Sets
# TILE_SKIPPED. Returns 0 on success, 1 if there is nothing to tile.
tile_collapse() {
    mkdir -p "$(dirname "$TOWER_TILE_MAP_FILE")" 2>/dev/null || true
    TILE_SKIPPED=0

    # 0. Recover from any prior/interrupted tile before rebuilding (NEVER a
    #    plain kill — that would strand already-joined panes).
    tile_disband || true
    session_tmux has-session -t "$TOWER_TILE_SESSION" 2>/dev/null &&
        session_tmux kill-session -t "$TOWER_TILE_SESSION" 2>/dev/null || true

    # 1. Collect tileable sessions: active tower_* with exactly ONE window.
    local sessions=() s wins
    while IFS= read -r s; do
        [[ "$s" == tower_* ]] || continue
        [[ "$s" == "$TOWER_TILE_SESSION" ]] && continue
        wins=$(session_tmux list-windows -t "$s" -F x 2>/dev/null | wc -l)
        if [[ "$wins" -ne 1 ]]; then
            TILE_SKIPPED=$((TILE_SKIPPED + 1))
            continue
        fi
        sessions+=("$s")
    done < <(session_tmux list-sessions -F '#{session_name}' 2>/dev/null | sort)

    if [[ ${#sessions[@]} -eq 0 ]]; then
        return 1
    fi

    # 2. Dedicated tile session + a holder pane we kill once panes are joined.
    session_tmux new-session -d -s "$TOWER_TILE_SESSION" -n tile \
        -x "$(tput cols 2>/dev/null || echo 200)" \
        -y "$(tput lines 2>/dev/null || echo 50)"
    local holder tw
    holder=$(session_tmux display-message -p -t "$TOWER_TILE_SESSION" '#{pane_id}')
    tw=$(session_tmux display-message -p -t "$TOWER_TILE_SESSION" '#{window_id}')

    # Orientation cues (the deleted tile-pane.conf had turned these off).
    session_tmux set-option -t "$TOWER_TILE_SESSION" pane-border-status top 2>/dev/null || true
    session_tmux set-option -t "$TOWER_TILE_SESSION" pane-border-format ' #{@tower_name} ' 2>/dev/null || true
    session_tmux set-option -t "$TOWER_TILE_SESSION" pane-active-border-style 'fg=green,bold' 2>/dev/null || true
    session_tmux set-option -w -t "$tw" monitor-activity on 2>/dev/null || true

    # 3. For each session: explicit claude pane, holder FIRST, tag, record,
    #    join, and re-tile after EVERY join (Bug 3: join-then-tile-once fails
    #    "pane too small" at N>=4).
    : >"${TOWER_TILE_MAP_FILE}.tmp"
    local p
    for s in "${sessions[@]}"; do
        p=$(session_tmux list-panes -t "${s}:claude" -F '#{pane_id}' 2>/dev/null | head -1)
        [[ -n "$p" ]] || continue
        session_tmux new-window -d -t "$s" -n "$TOWER_TILE_HOLDER_WINDOW" \
            "exec sleep 2147483647"
        session_tmux set-option -p -t "$p" @tower_name "$s"
        printf '%s\t%s\n' "$p" "$s" >>"${TOWER_TILE_MAP_FILE}.tmp"
        session_tmux join-pane -s "$p" -t "$tw"
        session_tmux select-layout -t "$tw" tiled
    done
    mv "${TOWER_TILE_MAP_FILE}.tmp" "$TOWER_TILE_MAP_FILE"

    # 4. Drop holder, final layout, focus first pane.
    session_tmux kill-pane -t "$holder" 2>/dev/null || true
    session_tmux select-layout -t "$tw" tiled
    session_tmux select-pane -t "${tw}.0" 2>/dev/null || true
    return 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/bats/bin/bats tests/integration/test_tile_join_pane.bats -f "tile_collapse"`
Expected: PASS (6 tests).

- [ ] **Step 5: Run the whole tile suite**

Run: `./tests/bats/bin/bats tests/integration/test_tile_join_pane.bats`
Expected: PASS (all tests from Tasks 1-3).

- [ ] **Step 6: Commit**

```bash
git add tmux-plugin/lib/tile.sh tests/integration/test_tile_join_pane.bats
git commit -m "feat(tile): implement size-stable tile_collapse via join-pane"
```

---

## Task 4: Create `tile-exit.sh` (focus capture → disband → re-enter Navigator)

**Files:**
- Create: `tmux-plugin/scripts/tile-exit.sh`
- Test: `tests/integration/test_tile_join_pane.bats`

- [ ] **Step 1: Write the failing test**

The script `exec`s into the Navigator at the end, which we can't run headless.
Test the parts we can: that it is executable, sources cleanly, and that running
it on a built tile state disbands and writes a warning only on anomaly. We
stub the re-enter step via an env hook.

Append:

```bash
@test "tile-exit.sh: disbands tile and restores sessions" {
    make_claude p; make_claude q
    tile_collapse
    # TOWER_TILE_NO_REENTER short-circuits the navigator exec for tests.
    TOWER_TILE_NO_REENTER=1 run "$PROJECT_ROOT/tmux-plugin/scripts/tile-exit.sh"
    [ "$status" -eq 0 ]
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_p
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_q
    ! TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower-tile
}

@test "tile-exit.sh: writes a warning on teardown anomaly" {
    make_claude r
    tile_collapse
    # Corrupt the map so one entry references a dead pane.
    printf '%s\t%s\n' "%999" tower_ghost >>"$TOWER_TILE_MAP_FILE"
    TOWER_TILE_NO_REENTER=1 run "$PROJECT_ROOT/tmux-plugin/scripts/tile-exit.sh"
    # Warning file exists for the Navigator to surface.
    [ -f "$TOWER_NAV_WARNING_FILE" ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/bats/bin/bats tests/integration/test_tile_join_pane.bats -f "tile-exit"`
Expected: FAIL — script does not exist.

- [ ] **Step 3: Create `tmux-plugin/scripts/tile-exit.sh`**

```bash
#!/usr/bin/env bash
# tile-exit.sh - leave Tile View: disband the grid, restore each session,
# and re-enter the Navigator with the focused session selected.
#
# Invoked server-side by the tile session's `prefix+Tab` binding and its
# `client-detached` hook (both installed by tile_collapse's caller). Runs on
# the SESSION server; must NOT assume a tty until the final re-enter.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/error-recovery.sh"
source "$SCRIPT_DIR/../lib/tile.sh"

# Capture focus BEFORE teardown moves panes around.
focused=$(session_tmux display-message -p -t "$TOWER_TILE_SESSION" \
    '#{@tower_name}' 2>/dev/null || echo "")

if ! tile_disband; then
    set_nav_warning "Tile teardown incomplete — run 'make status'"
fi

[[ -n "$focused" ]] && set_nav_selected "$focused"

# Re-enter the Navigator (Tab in -> prefix+Tab out is a reversible round trip).
# Tests set TOWER_TILE_NO_REENTER to stop before the exec.
[[ -n "${TOWER_TILE_NO_REENTER:-}" ]] && exit 0
TMUX= exec "$SCRIPT_DIR/navigator.sh" --direct
```

- [ ] **Step 4: Make it executable**

Run: `chmod +x tmux-plugin/scripts/tile-exit.sh`

- [ ] **Step 5: Run test to verify it passes**

Run: `./tests/bats/bin/bats tests/integration/test_tile_join_pane.bats -f "tile-exit"`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add tmux-plugin/scripts/tile-exit.sh tests/integration/test_tile_join_pane.bats
git commit -m "feat(tile): add tile-exit.sh (disband + return to Navigator)"
```

---

## Task 5: Rewrite `switch_to_tile` to use `tile_collapse` + install exit wiring

**Files:**
- Modify: `tmux-plugin/scripts/navigator-list.sh` (replace `switch_to_tile`, lines ~576-663)
- Verify: `tmux-plugin/scripts/navigator-list.sh` sources `lib/tile.sh`

- [ ] **Step 1: Confirm where navigator-list.sh sources its libs**

Run: `grep -n "source .*lib/" tmux-plugin/scripts/navigator-list.sh`
Expected: line 12 sources `common.sh` (it does NOT source `error-recovery.sh`; `error_log` lives in `common.sh`). `lib/tile.sh` will be sourced right after line 12.

- [ ] **Step 2: Write the failing test (source-level assertions)**

In `tests/integration/test_navigator_new_keys.bats`, replace the two old tests
(`"Tile View: tile-pane.conf exists for nested-attach panes"` and
`"switch_to_tile orchestrates split-window + tiled layout"`, lines ~104-120) with:

```bash
@test "Tile View: tile-pane.conf has been removed" {
    [ ! -e "$PROJECT_ROOT/tmux-plugin/conf/tile-pane.conf" ]
}

@test "switch_to_tile delegates to tile_collapse and installs exit wiring" {
    local script="$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
    local body
    body=$(awk '/^switch_to_tile\(\)/,/^}/' "$script")
    echo "$body" | grep -q "tile_collapse"
    echo "$body" | grep -q "bind-key"
    echo "$body" | grep -q "client-detached"
    echo "$body" | grep -q "tile-exit.sh"
    # Old nested-attach mechanics are gone.
    ! echo "$body" | grep -q "tile-pane.conf"
    ! echo "$body" | grep -q "split-window"
}

@test "navigator-list.sh sources lib/tile.sh" {
    grep -q "lib/tile.sh" "$PROJECT_ROOT/tmux-plugin/scripts/navigator-list.sh"
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `./tests/bats/bin/bats tests/integration/test_navigator_new_keys.bats -f "tile_collapse"`
Expected: FAIL — body still references old mechanics; `tile_collapse` absent.

- [ ] **Step 4: Source `lib/tile.sh` in navigator-list.sh**

After the existing `source "$SCRIPT_DIR/../lib/common.sh"` line (line 12), add:

```bash
source "$SCRIPT_DIR/../lib/tile.sh"
```

- [ ] **Step 5: Replace the `switch_to_tile` function body**

Replace the entire `switch_to_tile() { ... }` (lines ~576-663) with:

```bash
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

    # Exit wiring, server-side: prefix+Tab disbands and returns to Navigator.
    # The session server's normal prefix is left intact, so native pane keys
    # (prefix+z zoom, prefix+arrow, prefix+o, prefix+{/}, prefix+q) keep working.
    session_tmux bind-key Tab run-shell -b "$SCRIPT_DIR/tile-exit.sh" 2>/dev/null || true
    session_tmux set-hook -t "$TOWER_TILE_SESSION" client-detached \
        "run-shell -b '$SCRIPT_DIR/tile-exit.sh'" 2>/dev/null || true

    # Hand the Navigator client over to the tile session.
    nav_tmux detach-client \
        -E "TMUX= tmux -L '$TOWER_SESSION_SOCKET' attach-session -t '$TOWER_TILE_SESSION'"
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `./tests/bats/bin/bats tests/integration/test_navigator_new_keys.bats`
Expected: PASS (including the three rewritten tests).

- [ ] **Step 7: Commit**

```bash
git add tmux-plugin/scripts/navigator-list.sh tests/integration/test_navigator_new_keys.bats
git commit -m "refactor(tile): switch_to_tile delegates to tile_collapse"
```

---

## Task 6: Delete `tile-pane.conf` and rewrite the e2e tile tests

**Files:**
- Delete: `tmux-plugin/conf/tile-pane.conf`
- Modify: `tests/e2e/test_navigator_uie2e.bats` (remove 6 old tile tests ~509-637, add 1 smoke test)

- [ ] **Step 1: Delete the obsolete config**

Run: `git rm tmux-plugin/conf/tile-pane.conf`

- [ ] **Step 2: Remove the old nested-attach tile tests**

In `tests/e2e/test_navigator_uie2e.bats`, delete these six `@test` blocks and the
`active_window_for()` helper that only they used (lines ~505-637):
- `"uie2e: tile-pane.conf disables prefix in nested-attach panes"`
- `"uie2e: Tab from Navigator creates a tower-tile window with one pane per active session"`
- `"uie2e: host-session tile pane targets the original window (no mirror recursion)"`
- `"uie2e: Tile panes use tile-pane.conf for nested attach"`
- `"uie2e: Tab with no active sessions stays in Navigator (no tile window created)"`
- `"uie2e: switch_to_tile kills any prior tower-tile before rebuilding"`

Also delete the now-unused `TILE_PANE_CONF=` line near the top (~line 18).

- [ ] **Step 3: Add a replacement smoke test**

In the same file, where the tile tests were, add:

```bash
@test "uie2e: Tab collapses active sessions into a tower-tile session" {
    skip_if_no_tmux
    make_active "uie2e_jp_a"
    make_active "uie2e_jp_b"

    launch_navigator
    wait_for_text "navigator:0.0" "uie2e_jp_a"
    nav_send "Tab"

    # tower-tile session appears on the session server with 2 panes.
    local attempt=0
    while ((attempt < 50)); do
        if TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower-tile 2>/dev/null; then
            break
        fi
        sleep 0.1; ((attempt++)) || true
    done
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower-tile
    local pc
    pc=$(TMUX= tmux -L "$SESSION_SOCKET" list-panes -t tower-tile 2>/dev/null | wc -l)
    [ "$pc" -eq 2 ]

    # Source sessions are kept alive by their holder windows.
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_uie2e_jp_a
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_uie2e_jp_b
}
```

- [ ] **Step 4: Run the e2e suite**

Run: `./tests/bats/bin/bats tests/e2e/test_navigator_uie2e.bats`
Expected: PASS — old tile tests gone, new smoke test passes, all other tests unaffected.

- [ ] **Step 5: Commit**

```bash
git add tmux-plugin/conf/tile-pane.conf tests/e2e/test_navigator_uie2e.bats
git commit -m "test(tile): delete tile-pane.conf, rewrite e2e tile tests for join-pane"
```

---

## Task 7: Add startup orphan sweep to plugin init

**Files:**
- Modify: `tmux-plugin/claude-tower.tmux` (after line 52, the metadata-dir mkdir)
- Test: `tests/integration/test_tile_join_pane.bats`

- [ ] **Step 1: Write the failing test**

Append to `tests/integration/test_tile_join_pane.bats`:

```bash
@test "tile_sweep_orphans: removes stray holder windows and tower-tile" {
    make_claude orphan
    # Simulate a crashed tile: a holder window with no map file.
    TMUX= tmux -L "$SESSION_SOCKET" new-window -d -t tower_orphan -n _tile_holder "exec /bin/sleep 600"
    TMUX= tmux -L "$SESSION_SOCKET" new-session -d -s tower-tile -n tile "exec /bin/sleep 600"
    rm -f "$TOWER_TILE_MAP_FILE"

    tile_sweep_orphans

    ! TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower-tile
    ! TMUX= tmux -L "$SESSION_SOCKET" list-windows -t tower_orphan -F '#{window_name}' | grep -q _tile_holder
    # The real session survives.
    TMUX= tmux -L "$SESSION_SOCKET" has-session -t tower_orphan
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/bats/bin/bats tests/integration/test_tile_join_pane.bats -f "sweep_orphans"`
Expected: FAIL — `tile_sweep_orphans: command not found`.

- [ ] **Step 3: Implement `tile_sweep_orphans` in `lib/tile.sh`**

Append:

```bash
# tile_sweep_orphans — startup recovery: kill any leftover tower-tile session
# and any _tile_holder window in any tower_X session, independent of the map
# file (which /tmp loses on reboot). Safe to call unconditionally.
tile_sweep_orphans() {
    session_tmux has-session -t "$TOWER_TILE_SESSION" 2>/dev/null &&
        session_tmux kill-session -t "$TOWER_TILE_SESSION" 2>/dev/null || true
    session_tmux list-windows -a \
        -F '#{session_name}:#{window_id} #{window_name}' 2>/dev/null |
        while read -r target name; do
            [[ "$name" == "$TOWER_TILE_HOLDER_WINDOW" ]] || continue
            session_tmux kill-window -t "${target%% *}" 2>/dev/null || true
        done
    rm -f "$TOWER_TILE_MAP_FILE" 2>/dev/null || true
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./tests/bats/bin/bats tests/integration/test_tile_join_pane.bats -f "sweep_orphans"`
Expected: PASS.

- [ ] **Step 5: Wire the sweep into plugin init**

In `tmux-plugin/claude-tower.tmux`, after line 52 (`mkdir -p "${CLAUDE_TOWER_METADATA_DIR...}"`), add:

```bash
# Clean up any tile artifacts orphaned by a crash/reboot (best effort).
"$CURRENT_DIR/scripts/tile-sweep.sh" 2>/dev/null || true
```

- [ ] **Step 6: Create the tiny `tile-sweep.sh` entry point**

Create `tmux-plugin/scripts/tile-sweep.sh`:

```bash
#!/usr/bin/env bash
# tile-sweep.sh - one-shot startup cleanup of orphaned Tile artifacts.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/error-recovery.sh"
source "$SCRIPT_DIR/../lib/tile.sh"
tile_sweep_orphans
```

Run: `chmod +x tmux-plugin/scripts/tile-sweep.sh`

- [ ] **Step 7: Commit**

```bash
git add tmux-plugin/lib/tile.sh tmux-plugin/scripts/tile-sweep.sh tmux-plugin/claude-tower.tmux tests/integration/test_tile_join_pane.bats
git commit -m "feat(tile): startup sweep for orphaned _tile_holder / tower-tile"
```

---

## Task 8: Surface the Navigator warning banner

**Files:**
- Modify: `tmux-plugin/scripts/navigator-list.sh` (the list-render path)
- Test: covered by Task 4's warning test + manual check

- [ ] **Step 1: Find where the list renders its header/footer**

Run: `grep -n "show_help\|footer\|NAV_C_ACCENT\|build_session_list\|render" tmux-plugin/scripts/navigator-list.sh | head -20`
Identify the function that draws the list each cycle (where a one-line banner can be printed at the top).

- [ ] **Step 2: Write the failing test**

Add to `tests/integration/test_tile_join_pane.bats`:

```bash
@test "get_nav_warning returns then clears the warning" {
    set_nav_warning "boom"
    [ "$(get_nav_warning)" = "boom" ]
    [ -z "$(get_nav_warning)" ]   # cleared after read
}
```

- [ ] **Step 3: Run test to verify it fails or passes**

Run: `./tests/bats/bin/bats tests/integration/test_tile_join_pane.bats -f "get_nav_warning"`
Expected: PASS already (helpers were added in Task 1). If FAIL, the helper isn't sourced — fix the source line.

- [ ] **Step 4: Render the banner in the list draw**

In the list-render function identified in Step 1, near the top of the drawn
output (after the "Sessions" header), add:

```bash
    local _warn
    _warn=$(get_nav_warning)
    if [[ -n "$_warn" ]]; then
        echo "  ${NAV_C_ACCENT}⚠ ${_warn}${NAV_C_NORMAL}"
    fi
```

- [ ] **Step 5: Verify nothing regressed in the Navigator render tests**

Run: `./tests/bats/bin/bats tests/e2e/test_navigator_uie2e.bats`
Expected: PASS (banner only appears when a warning is set, which these tests don't set).

- [ ] **Step 6: Commit**

```bash
git add tmux-plugin/scripts/navigator-list.sh tests/integration/test_tile_join_pane.bats
git commit -m "feat(tile): render teardown warning banner in Navigator"
```

---

## Task 9: Update docs (README + in-Navigator help)

**Files:**
- Modify: `README.md` (Tile section ~109-125)
- Modify: `tmux-plugin/scripts/navigator-list.sh` (help text ~316-342)

- [ ] **Step 1: Update the in-Navigator help text**

In the help text block (~316-342), ensure the Tile lines read:

```
    Tab          Enter Tile view (all sessions side-by-side)
```

and add, in a Tile-view subsection or note:

```
    In Tile view:
      prefix+Tab   Return to Navigator
      prefix+z     Zoom focused pane to fullscreen (and back)
      prefix+→/←   Move between panes
      prefix+t     Leave Tower entirely
```

- [ ] **Step 2: Update the README Tile section**

In `README.md` (~109-125), replace any nested-attach / `tower-tile window`
description with the join-pane model and the key table above. State that exiting
Tile returns to the Navigator with the focused session selected, and that native
tmux pane keys (`prefix+z`, `prefix+arrow`, `prefix+o`) work because tiles are
real panes.

- [ ] **Step 3: Verify docs mention no removed artifacts**

Run: `grep -rn "tile-pane.conf\|tower tile\|nested.attach" README.md docs/ | grep -v specs/ | grep -v plans/`
Expected: no stale references (other than in the spec/plan history docs).

- [ ] **Step 4: Commit**

```bash
git add README.md tmux-plugin/scripts/navigator-list.sh
git commit -m "docs(tile): document join-pane Tile, prefix+Tab exit, native zoom"
```

---

## Task 10: Full suite, lint, format

**Files:** none (verification only)

- [ ] **Step 1: Run shellcheck**

Run: `make lint`
Expected: no new findings. Fix any in the new files (`lib/tile.sh`, `tile-exit.sh`, `tile-sweep.sh`). Allowed excludes: SC2034, SC1091, SC2317.

- [ ] **Step 2: Check formatting**

Run: `make format`
Expected: clean. If not, run `make format-fix` and re-commit.

- [ ] **Step 3: Run the full test suite**

Run: `make test`
Expected: all bats suites pass (Unit, Integration, E2E), including the new `test_tile_join_pane.bats` and the rewritten tile assertions.

- [ ] **Step 4: Manual smoke test (inside a real tmux)**

```
make reset           # kill servers, clear caches, reload
# create 2-3 sessions via the Navigator (prefix+t, then n)
# press Tab -> grid appears, panes NOT shrunk to 1 row, each labeled
# press prefix+z on a pane -> zooms; prefix+z again -> back
# press prefix+Tab -> back in Navigator, focused session selected
# press prefix+t -> leaves Tower entirely
```
Expected: stable grid, working zoom, clean round-trip. This is the bug the whole plan fixes — confirm the shrink is gone.

- [ ] **Step 5: Final commit (if lint/format produced changes)**

```bash
git add -A
git commit -m "chore(tile): lint + format pass"
```

---

## Self-Review

**Spec coverage** (design doc → task):
- join-pane collapse, single client, no shrink → Task 3 + Task 10 smoke
- placeholder `_tile_holder` keeps sessions alive → Task 3 (test asserts), Task 2 (disband)
- `@tower_name` tag + atomic map file → Task 3
- crash-safe / idempotent teardown → Task 2
- `:claude` explicit pane, multi-window skip → Task 3 (tests)
- per-join `select-layout tiled` (Bug 3) → Task 3
- prefix+Tab exit, native keys preserved, exit→Navigator, focus restore → Task 4 + Task 5 + Task 9
- prefix+t stays global leave-Tower → unchanged (Task 5 leaves `install_return_binding` alone); documented Task 9
- orientation cues (border labels, active border, monitor-activity) → Task 3
- skipped-session notice → Task 3 (TILE_SKIPPED) + Task 5 (display-message)
- audible teardown failure → Task 2 (error_log + rc) + Task 4 (warning) + Task 8 (banner)
- startup orphan sweep → Task 7
- delete tile-pane.conf, rewrite tests → Task 5, Task 6
- docs → Task 9
- lint/format/full suite → Task 10

**Placeholder scan:** No TBD/TODO; every code step contains complete code.

**Type/name consistency:** `tile_collapse`, `tile_disband`, `tile_sweep_orphans`,
`TILE_SKIPPED`, `TOWER_TILE_SESSION`, `TOWER_TILE_HOLDER_WINDOW`,
`TOWER_TILE_MAP_FILE`, `TOWER_NAV_WARNING_FILE`, `set_nav_warning`/`get_nav_warning`,
`TOWER_TILE_NO_REENTER` — used identically across all tasks.

**Known soft spots to watch during execution:**
- `tput cols/lines` returns the *navigator client's* size at tile-create time;
  a later terminal resize re-tiles via tmux's own redraw. Task 10 smoke covers it.
- `client-detached` hook also fires on accidental `prefix+d` — intended (disbands
  and returns to Navigator); documented in the design doc edge cases.
- The e2e harness can't drive a full client into the tile, so the *interactive*
  exit (`prefix+Tab` keypress) is covered by the function-level `tile-exit.sh`
  tests (Task 4) plus the Task 10 manual smoke, not an automated keypress test.
