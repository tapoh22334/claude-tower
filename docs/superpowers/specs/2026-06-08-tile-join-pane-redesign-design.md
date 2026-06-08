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
sessions=()
while IFS= read -r s; do
    [[ "$s" == tower_* ]] || continue
    [[ $(session_tmux list-windows -t "$s" -F x | wc -l) -eq 1 ]] || continue
    sessions+=("$s")
done < <(session_tmux list-sessions -F '#{session_name}' | sort)
[[ ${#sessions[@]} -eq 0 ]] && { echo "No tileable sessions"; sleep 0.8; return; }

# 2. dedicated tile session + holder pane
session_tmux new-session -d -s tower-tile -n tile -x "$(tput cols)" -y "$(tput lines)"
HOLDER=$(session_tmux display-message -p -t tower-tile '#{pane_id}')
TW=$(session_tmux display-message -p -t tower-tile '#{window_id}')

# 3. per session: explicit :claude pane, add holder FIRST, tag, record, join, tile each time
: > "$MAP.tmp"
for s in "${sessions[@]}"; do
    P=$(session_tmux list-panes -t "$s:claude" -F '#{pane_id}' | head -1)
    session_tmux new-window -d -t "$s" -n _tile_holder "exec sleep 2147483647"
    session_tmux set-option -p -t "$P" @tower_name "$s"
    printf '%s\t%s\n' "$P" "$s" >> "$MAP.tmp"
    session_tmux join-pane -s "$P" -t "$TW"
    session_tmux select-layout -t "$TW" tiled          # every join (BUG3)
done
mv "$MAP.tmp" "$MAP"

# 4. drop holder, final layout, focus
session_tmux kill-pane -t "$HOLDER"
session_tmux select-layout -t "$TW" tiled
session_tmux select-pane -t "$TW".0

# 5. server-side teardown hook (prefix+t) + detach safety net
session_tmux bind-key t run-shell -b "$SCRIPT_DIR/tile-exit.sh"
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
_tile_teardown() {
    [[ -f "$MAP" ]] || return 0
    while IFS=$'\t' read -r PANE SESS; do
        session_tmux list-panes -a -F '#{pane_id}' | grep -qx "$PANE" || continue  # crash skip
        if session_tmux has-session -t "$SESS" 2>/dev/null; then
            session_tmux join-pane -s "$PANE" -t "$SESS:_tile_holder"
            session_tmux kill-window -t "$SESS:_tile_holder" 2>/dev/null || true
            session_tmux rename-window -t "$SESS:" claude 2>/dev/null || true
        else
            session_tmux new-session -d -s "$SESS" -n claude
            PH=$(session_tmux display-message -p -t "$SESS" '#{pane_id}')
            session_tmux join-pane -s "$PANE" -t "$SESS:"
            session_tmux kill-pane -t "$PH"
        fi
    done < "$MAP"
    rm -f "$MAP"
    session_tmux has-session -t tower-tile 2>/dev/null && \
        session_tmux kill-session -t tower-tile
}
```

## Bugs found in adversarial review and how the design handles them

| # | Bug (proven on tmux 3.6a) | Fix |
|---|---|---|
| 1 | `list-panes \| head -1` grabs the active window; multi-window `tower_X` (e.g. `tower_makyo` has 3) → wrong pane tiled, EXIT `kill-session` destroys Claude; recreate collides ("duplicate session"). | Target `:claude` explicitly; skip multi-window sessions at enter; EXIT never `kill-session`s an existing target. |
| 2 | Interrupted ENTER + next ENTER's plain `kill-session tower-tile` destroys already-joined sessions, unrecoverable. | Sweep runs `_tile_teardown` (disband, join panes back) before any kill; map written atomically. |
| 3 | Join-all-then-tile-once fails "pane too small" at N≳4, regardless of window size. | `select-layout tiled` after every join. |
| 4 | Current prefix+t (`install_return_binding` → `detach-client -E`) runs client-side; teardown must run on the session server. No hook exists. | Dedicated server-side `tile-exit.sh` binding + `client-detached` hook; teardown runs before return. |
| 5 | If `tower_X` vanishes mid-tile, Navigator poll reclassifies all as DORMANT (flicker) and `r` could double-spawn a live Claude. | Resident `_tile_holder` keeps every `tower_X` alive during tile. |
| 6 | `$TOWER_STATE_DIR` does not exist; `~/.claude-tower/tile.map` dir not guaranteed; exit returns to the default-server caller, not the Navigator. | Use `$TOWER_NAV_STATE_DIR/tile.map` (real var) + `ensure_nav_state_dir`; teardown returns deliberately (see Open question). |

## Edge cases

- **Claude crashes while tiled**: its pane disappears; EXIT's pane-existence
  check skips it; its `_tile_holder` keeps the session, removed on teardown if
  Claude is gone. No orphan.
- **Re-entering tile**: ENTER's disband-sweep makes it idempotent.
- **Sessions added/removed between enter and exit**: teardown is driven by the
  map; missing panes skip, missing sessions recreate.
- **No tileable sessions**: ENTER returns to Navigator with a message.

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
restores every `tower_X` by name with same PID; multi-window skipped; crashed
pane skipped on exit; interrupted enter recovers; 4+ sessions tile without
"pane too small"; placeholder keeps `tower_X` alive during tile.

**New Integration**: `tile-exit.sh` picks the right `has-session` branch;
`switch_to_tile` body includes `:claude`, per-join tiled, atomic `mv`;
server-side binding + `client-detached` hook installed.

## Open question (resolve in implementation)

After Tile exit, where does the user land? Today `return-to-caller.sh` returns
to the original default-server session, not the Navigator. `tile-exit.sh` should
decide deliberately — most likely re-enter the Navigator (`navigator.sh
--direct`) so Tab→Tile→prefix+t is a round trip back to the control center, not
a one-way exit out of Tower. Confirm during implementation.

## Files

- `lib/tile.sh` — **new**, shared `_tile_teardown` (sourced by both call sites)
- `scripts/navigator-list.sh` — rewrite `switch_to_tile` (577-663)
- `scripts/tile-exit.sh` — **new**, server-side teardown entry + return home
- `conf/tile-pane.conf` — **delete**
- `lib/common.sh` — add `tile.map` path constant if desired
- `tests/e2e/test_navigator_uie2e.bats`, `tests/integration/test_navigator_new_keys.bats` — rewrite tile tests
