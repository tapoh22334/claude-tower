# Tile View Redesign: nested-attach → join-pane

**Date**: 2026-06-08
**Status**: Approved design, pending implementation
**Branch context**: 003-simplify

## Problem

Entering Tile mode shrinks each pane down to a single row. The display
collapses by ~1 row every redraw cycle until it is unusable.

### Root cause

The current Tile View nests a live `tmux attach-session -t tower_X` client
*inside* each tile pane (a "client-in-a-pane" mirror — see
`scripts/navigator-list.sh:577-663` and `conf/tile-pane.conf`). Each nested
attach is a real extra client on the session server. A `tower_X` session is
then attached by two clients of different sizes (the small tile pane and any
original full-size client).

Empirically (tmux 3.6a), the spiral is driven by **mirror-recursion**: when
the `tower-tile` window is the session's active window and a tile pane
nested-attaches to the bare session name, that attach resolves to the very
window it lives in. tmux renders the window inside one of its own panes and the
feedback loop crushes it (measured: window collapsing to 250x3, neighbour to
250x1). Recent commits patched specific instances of this recursion, but the
nested-attach approach remains structurally fragile — one stray active-window
change re-triggers the spiral.

(Note: tmux 3.6a's default `window-size` is `latest`, not `smallest`, so two
static clients of different sizes do **not** by themselves cause the spiral.
The recursion is the cause.)

## Approach

Replace nested-attach with **native pane relocation via `join-pane`**. All
active `tower_X` sessions' Claude panes are moved into a single dedicated
`tower-tile` session's window. Because the tile is then viewed by exactly **one**
client, there is no size negotiation and no recursion — the shrink is
structurally impossible.

This was validated end-to-end on tmux 3.6a by five independent design agents
and three adversarial reviewers. Validated facts:

- `join-pane` across sessions on one server is size-stable (single client).
- It preserves the running process, PID, and scrollback (one clean SIGWINCH).
- A pane-scoped `@tower_name` user option survives join in and back out.
- `select-layout tiled` after **every** join yields a clean near-square grid;
  joining all panes first then tiling once fails with "pane too small" at N≳4.
- The tile session auto-destroys when its last pane leaves.

### Architecture

```
session server (-L claude-tower-sessions)

normal:
  tower_A [win:claude (pane %0)]
  tower_B [win:claude (pane %1)]
  tower_C [win:claude (pane %2)]

tiled:                         ← join-pane relocation, single client
  tower_A [win:_tile_holder]   ← placeholder keeps the session alive
  tower_B [win:_tile_holder]
  tower_C [win:_tile_holder]
  tower-tile [win:tile ┌──%0──┬──%1──┐ ]
                       │  A    │  B    │
                       ├──%2───┴───────┤
                       │  C    │       │
                       └───────────────┘
```

**Key decision — placeholder stays resident for the whole tile lifetime.**
Each `tower_X` keeps a `_tile_holder` window (a no-op `sleep`) while its Claude
pane lives in `tower-tile`, so the `tower_X` session is never destroyed. This is
what makes the Navigator list stable during Tile and makes exit a simple
join-back rather than a session-recreate.

`conf/tile-pane.conf` is **removed** — there are no nested clients anymore.

### State

- Pane tag: `set-option -p -t <pane> @tower_name <tower_X>` (survives joins).
- Map file: `$TOWER_NAV_STATE_DIR/tile.map` (`/tmp/claude-tower/tile.map`),
  lines of `pane_id<TAB>session_name`, written atomically (`.tmp` + `mv`).
- The map is the teardown's source of truth; `@tower_name` is a redundant
  cross-check.

## Data flow

### ENTER (`switch_to_tile`)

```bash
SOCK="$TOWER_SESSION_SOCKET"
MAP="$TOWER_NAV_STATE_DIR/tile.map"
ensure_nav_state_dir

# 0. disband-sweep: recover from an interrupted prior run (NEVER plain kill)
[[ -f "$MAP" ]] && _tile_teardown
session_tmux has-session -t tower-tile 2>/dev/null && \
    session_tmux kill-session -t tower-tile

# 1. tileable = active tower_* with exactly ONE window (multi-window skipped)
sessions=(); skipped=0
while IFS= read -r s; do
    [[ "$s" == tower_* ]] || continue
    if [[ $(session_tmux list-windows -t "$s" -F x | wc -l) -ne 1 ]]; then
        skipped=$((skipped + 1)); continue       # multi-window: skip (BUG1), count it
    fi
    sessions+=("$s")
done < <(session_tmux list-sessions -F '#{session_name}' | sort)
[[ ${#sessions[@]} -eq 0 ]] && { echo "No tileable sessions"; sleep 0.8; return; }

# 2. dedicated tile session + holder pane
session_tmux new-session -d -s tower-tile -n tile -x "$(tput cols)" -y "$(tput lines)"
HOLDER=$(session_tmux display-message -p -t tower-tile '#{pane_id}')
TW=$(session_tmux display-message -p -t tower-tile '#{window_id}')

# orientation: label each pane with its session name on the border (UX review)
session_tmux set-option -t tower-tile pane-border-status top
session_tmux set-option -t tower-tile pane-border-format ' #{@tower_name} '
session_tmux set-option -t tower-tile pane-active-border-style 'fg=green,bold'
session_tmux set-option -w -t "$TW" monitor-activity on   # surface which Claude is busy

# 3. per session: explicit :claude pane, add holder FIRST, tag, record, join, tile each time
: > "$MAP.tmp"
for s in "${sessions[@]}"; do
    P=$(session_tmux list-panes -t "$s:claude" -F '#{pane_id}' | head -1)
    session_tmux new-window -d -t "$s" -n _tile_holder "exec sleep 2147483647"
    session_tmux set-option -p -t "$P" @tower_name "$s"   # single source of truth
    printf '%s\t%s\n' "$P" "$s" >> "$MAP.tmp"
    session_tmux join-pane -s "$P" -t "$TW"
    session_tmux select-layout -t "$TW" tiled          # every join (BUG3)
done
mv "$MAP.tmp" "$MAP"

# 4. drop holder, final layout, focus; warn about skipped multi-window sessions
session_tmux kill-pane -t "$HOLDER"
session_tmux select-layout -t "$TW" tiled
session_tmux select-pane -t "$TW".0
[[ $skipped -gt 0 ]] && session_tmux display-message -t tower-tile \
    "$skipped multi-window session(s) skipped"

# 5. Exit binding + detach safety net.
#    The tile panes are LIVE Claude — bare keys (Tab, Escape, q) MUST pass
#    through to Claude, so the exit cannot be a bare key. It is a prefix key:
#    `prefix+Tab` exits Tile (mnemonic: Tab entered it). The session server's
#    normal prefix is intact, so native pane keys (prefix+z zoom, prefix+arrow,
#    prefix+o, prefix+{/}, prefix+q) are PRESERVED and must not be stripped.
session_tmux bind-key Tab run-shell -b "$SCRIPT_DIR/tile-exit.sh"
session_tmux set-hook -t tower-tile client-detached "run-shell -b '$SCRIPT_DIR/tile-exit.sh'"

# 6. hand client to tile
nav_tmux detach-client -E "TMUX= tmux -L '$SOCK' attach-session -t tower-tile"
```

### EXIT (`tile-exit.sh`, runs on the session server)

`_tile_teardown` is defined in `tile-exit.sh` and is the body of the teardown.
`tile-exit.sh` (invoked by the binding/hook) sources its definition and calls
it, then returns the client home. ENTER (in `navigator-list.sh`) reuses the same
function for its step-0 disband-sweep — extract it into a small shared sourceable
file (e.g. `lib/tile.sh`) so both call sites share one implementation.

```bash
# _tile_teardown disbands the tile, returning every pane to its session.
# It does NOT attach anywhere — pure state repair, reused by ENTER's sweep.
# Returns 0 if clean, 1 if any anomaly (so callers can warn the user).
_tile_teardown() {
    [[ -f "$MAP" ]] || return 0
    local rc=0
    while IFS=$'\t' read -r PANE SESS; do
        if ! session_tmux list-panes -a -F '#{pane_id}' | grep -qx "$PANE"; then
            error_log "tile teardown: pane $PANE ($SESS) gone (Claude exited); skipping"
            rc=1; continue                                   # crash skip — but LOUD
        fi
        if session_tmux has-session -t "$SESS" 2>/dev/null; then
            session_tmux join-pane -s "$PANE" -t "$SESS:_tile_holder" || rc=1
            session_tmux kill-window -t "$SESS:_tile_holder" 2>/dev/null || true
            session_tmux rename-window -t "$SESS:" claude 2>/dev/null || true
        else
            session_tmux new-session -d -s "$SESS" -n claude || rc=1
            PH=$(session_tmux display-message -p -t "$SESS" '#{pane_id}')
            session_tmux join-pane -s "$PANE" -t "$SESS:" || rc=1
            session_tmux kill-pane -t "$PH" 2>/dev/null || true
        fi
    done < "$MAP"
    rm -f "$MAP"
    session_tmux has-session -t tower-tile 2>/dev/null && \
        session_tmux kill-session -t tower-tile
    return $rc
}
```

`tile-exit.sh` wraps `_tile_teardown` and returns the client to the Navigator,
selecting the session that was focused at exit time:

```bash
# capture focus BEFORE teardown moves panes around
FOCUSED=$(session_tmux display-message -p -t tower-tile '#{@tower_name}' 2>/dev/null)

if _tile_teardown; then :; else
    # anomaly: leave a breadcrumb the user will actually see in the Navigator
    set_nav_warning "Tile teardown incomplete — run 'make status'"
fi

[[ -n "$FOCUSED" ]] && set_nav_selected "$FOCUSED"   # restore Navigator cursor

# return to the Navigator (Tab in -> prefix+Tab out is a reversible round trip)
TMUX= exec "$SCRIPT_DIR/navigator.sh" --direct
```

## Bugs found in adversarial review and how the design handles them

| # | Bug (proven on tmux 3.6a) | Fix |
|---|---|---|
| 1 | `list-panes \| head -1` grabs the active window; multi-window `tower_X` (e.g. `tower_makyo` has 3) → wrong pane tiled, EXIT `kill-session` destroys Claude; recreate collides ("duplicate session"). | Target `:claude` explicitly; skip multi-window sessions at enter; EXIT never `kill-session`s an existing target. |
| 2 | Interrupted ENTER + next ENTER's plain `kill-session tower-tile` destroys already-joined sessions, unrecoverable. | Sweep runs `_tile_teardown` (disband, join panes back) before any kill; map written atomically. |
| 3 | Join-all-then-tile-once fails "pane too small" at N≳4, regardless of window size. | `select-layout tiled` after every join. |
| 4 | Current prefix+t (`install_return_binding` → `detach-client -E`) runs client-side; teardown must run on the session server. No hook exists. | Dedicated server-side `tile-exit.sh` binding + `client-detached` hook; teardown runs before return. |
| 5 | If `tower_X` vanishes mid-tile, Navigator poll reclassifies all as DORMANT (flicker) and `r` could double-spawn a live Claude. | Resident `_tile_holder` keeps every `tower_X` alive during tile. |
| 6 | `$TOWER_STATE_DIR` does not exist; `~/.claude-tower/tile.map` dir not guaranteed; exit returns to the default-server caller, not the Navigator. | Use `$TOWER_NAV_STATE_DIR/tile.map` (real var) + `ensure_nav_state_dir`; teardown re-enters the Navigator (see Interaction model). |

## Interaction model (UX review)

Reviewed from a senior tmux-user perspective. Decisions:

- **Enter / exit is a reversible toggle.** `Tab` enters Tile from the Navigator;
  `prefix+Tab` exits back to the Navigator. (Exit is a *prefix* key, not bare —
  the tile panes are live Claude, so bare `Tab`/`Escape`/`q` must pass through
  to Claude. `prefix+Tab` mnemonically pairs with the `Tab` that entered.)
- **`prefix+t` keeps its global meaning** ("leave Tower entirely") everywhere,
  including inside Tile. We do NOT overload it for Tile exit. Two verbs, two keys.
- **Exit lands in the Navigator**, with the cursor on whichever session was
  focused in the grid at exit time (`@tower_name` of the focused pane →
  `set_nav_selected`). Tile is a *view* of the Navigator, not a destination.
- **Native pane keys are preserved.** Because tiles are real panes on the
  session server (normal prefix intact), `prefix+z` (zoom — the actual work
  surface for "now drive THIS one"), `prefix+arrow`, `prefix+o`, `prefix+{`/`}`,
  `prefix+q` all Just Work. This is the dividend of removing nested clients. The
  design must NOT strip the prefix; a test asserts these still resolve. We do not
  reimplement zoom/navigation — tmux owns it.
- **Orientation cues**: each pane is labeled with its session name via
  `pane-border-status top` + `@tower_name`; the active pane has a bold green
  border; `monitor-activity on` surfaces which Claude is busy. (The deleted
  `tile-pane.conf` had turned all of these off.)
- **Skipped sessions are surfaced**: multi-window sessions excluded for safety
  (Bug 1) trigger a one-line `display-message` so their absence isn't silent.
- **Failures are audible**: teardown routes every skip/failure through
  `error_log`; on any anomaly the user lands in the Navigator with a warning
  banner ("Tile teardown incomplete — run `make status`"), since a backgrounded
  `run-shell` hook has nowhere to print.

## Edge cases

- **Claude crashes while tiled**: its pane disappears; EXIT's pane-existence
  check skips it; its `_tile_holder` keeps the session, removed on teardown if
  Claude is gone. No orphan.
- **Re-entering tile**: ENTER's disband-sweep makes it idempotent.
- **Sessions added/removed between enter and exit**: teardown is driven by the
  map; missing panes skip, missing sessions recreate.
- **No tileable sessions**: ENTER returns to Navigator with a message.
- **Orphaned `_tile_holder` after a hard crash / reboot**: if the host is
  rebooted mid-tile, `/tmp/claude-tower/tile.map` is lost, leaving `_tile_holder`
  windows in `tower_X` sessions with no recovery path — the "exactly one window"
  filter would then permanently exclude them from Tile. **Plugin init
  (`claude-tower.tmux`) runs an unconditional sweep**: kill any `_tile_holder`
  window and any leftover `tower-tile` session at startup, independent of the
  map file. One-liner, closes the orphan path entirely.
- **Accidental `prefix+d` inside Tile**: the `client-detached` hook fires the
  teardown — the tile disbands and sessions are restored. Correct outcome, just
  documented so it isn't surprising.

## Testing

Replace old nested-attach assertions; add a regression test per bug above. All
tests use `sleep` as the Claude stand-in for PID tracking; set
`CLAUDE_TOWER_SESSION_SOCKET` / `TMUX_TMPDIR` before `source_common`; run under
Docker isolation (`make test`).

**Remove / rewrite** (old behavior):
- `tests/e2e/test_navigator_uie2e.bats`: L519, L552, L590, L513, L615, L627
- `tests/integration/test_navigator_new_keys.bats`: L104, L110
- `conf/tile-pane.conf` existence assertions

**New E2E**: collapse into tower-tile session; pane tag + map agree; exit
restores every `tower_X` by name with same PID; multi-window skipped (with
visible notice); crashed pane skipped on exit; interrupted enter recovers; 4+
sessions tile without "pane too small"; placeholder keeps `tower_X` alive during
tile; **exit returns to Navigator with the focused session selected**; **native
`prefix+z` / `prefix+arrow` still resolve on the tile session** (prefix not
stripped); **startup sweep removes orphaned `_tile_holder` / `tower-tile`**.

**New Integration**: `tile-exit.sh` picks the right `has-session` branch and
re-enters the Navigator; `_tile_teardown` returns non-zero on anomaly and sets a
warning; `switch_to_tile` body includes `:claude`, per-join tiled, atomic `mv`,
`pane-border-status`, `monitor-activity`; `prefix+Tab` exit binding +
`client-detached` hook installed; `prefix+t` remains the global leave-Tower key.

## Decided (was open)

**Exit lands in the Navigator** (see Interaction model). `tile-exit.sh`
re-enters via `navigator.sh --direct` and restores the cursor to the focused
session. `prefix+t` is untouched and still means "leave Tower entirely."

## Files

- `lib/tile.sh` — **new**, shared `_tile_teardown` (sourced by both call sites)
- `scripts/navigator-list.sh` — rewrite `switch_to_tile` (577-663); `Tab` key in
  the handler enters Tile
- `scripts/tile-exit.sh` — **new**, server-side teardown entry + re-enter Navigator
- `conf/tile-pane.conf` — **delete**
- `lib/common.sh` — `tile.map` path constant; `set_nav_warning`/`get_nav_warning`
  helpers (Navigator renders the banner on next draw)
- `claude-tower.tmux` — add startup orphan sweep (`_tile_holder` / `tower-tile`)
- `scripts/navigator-list.sh` help text + `README.md` Tile section — document
  `Tab` in / `prefix+Tab` out / `prefix+t` leaves Tower / `prefix+z` zoom
- `tests/e2e/test_navigator_uie2e.bats`, `tests/integration/test_navigator_new_keys.bats` — rewrite tile tests
