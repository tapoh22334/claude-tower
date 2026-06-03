# Phase 0 Research: Simplification

**Date**: 2026-06-03
**Feature**: 003-simplify

All UX-level ambiguities were resolved in the spec Clarifications session (2026-06-03). This document captures the code-archaeology findings needed to implement the changes safely.

## Decision: Dead Code Inventory

**Decision**: The following 11 scripts have zero callers from `bin/tower`, other scripts, or tmux key bindings (verified via grep):

| File | Reason |
|---|---|
| `scripts/sidebar.sh` | Sidebar feature being removed entirely (FR-014) |
| `scripts/new-session.sh` | Only called by `sidebar.sh:155`; dies with Sidebar |
| `scripts/tree-view.sh` | v1 prefix-w style tree; no callers |
| `scripts/help.sh` | "SPECIFICATION.md v3.2" legacy help; no callers |
| `scripts/diff.sh` | Workspace-diff (v1 concept); no callers |
| `scripts/kill.sh` | Generic kill; no callers |
| `scripts/rename.sh` | Rename; no callers |
| `scripts/input.sh` | Old input-mode entry; replaced by navigator-view's `i` |
| `scripts/preview.sh` | fzf preview (fzf not used); no callers |
| `scripts/session-new.sh` | Explicitly marked DEPRECATED in header |
| `scripts/cleanup.sh` | Orphan; only README references it |

**Rationale**: All 11 are verified unreachable through static analysis. README references can be updated in the same change.

**Alternatives considered**: Mark as deprecated but keep — rejected per Constitution V (Simplicity) and the user's "余分なものがあったら消したい" directive.

## Decision: Worktree Residue Removal

**Decision**: Remove the following worktree-related residues:

1. `claude-tower.tmux:49` — `mkdir -p "${CLAUDE_TOWER_WORKTREE_DIR:-$HOME/.claude-tower/worktrees}"` (creates an unused directory).
2. Any v1 worktree code branches in `session-add.sh`, `session-restore.sh`, `lib/common.sh` (to be audited during implementation).

**Rationale**: Claude Code now ships `claude wt`; Tower must not appear to manage worktrees (Constitution I).

**Alternatives considered**: Leave the mkdir as harmless — rejected; it creates user confusion and contradicts Constitution I.

## Decision: Navigator's `n` Implementation

**Decision**: Add an inline single-line prompt at the bottom of `navigator-list.sh` triggered by the `n` key. The prompt:

- Prefills with the **caller's working directory**. The caller CWD is already captured via `/tmp/claude-tower/caller` (set by `claude-tower.tmux` when launching Navigator); however, that file stores `session_name`, not a CWD. **Need to capture CWD at Navigator launch time** — extend the run-shell snippet in `claude-tower.tmux` to also write `pwd` of the caller session to a sibling file (e.g., `/tmp/claude-tower/caller-cwd`).
- Reads input via `read -e -i "$default_path"` (Bash readline editing).
- On Enter, invokes `session-add.sh "$path"` (no `-n` from Navigator per Clarifications Q1).
- On empty input or Escape, returns to the list with no change.

**Rationale**: Reuses the existing `session-add.sh` codepath (no business logic duplication). Inline prompt matches the spec's "no modal" preference.

**Alternatives considered**:
- Spawn a separate tmux popup window for the prompt — rejected as overengineered for a single path input.
- Write a new Bash helper for path entry — rejected; `read -e` is sufficient.

## Decision: Navigator's `d` Implementation

**Decision**: Inline prompt `Delete '<name>'? [y/N]` triggered by `d`. Only literal `y` (lowercase) confirms; any other key cancels. Invokes `session-delete.sh "$name" -f` after confirmation (the `-f` bypasses the CLI's own confirmation since Navigator already confirmed).

**Rationale**: Reuses existing `session-delete.sh`. Single-char read keeps UX snappy. Lowercase-only confirmation reduces accidental destructive presses.

**Alternatives considered**:
- `Y/n` (default-yes) — rejected; defaults must favor safety for destructive ops.
- Two-step `dd` — rejected per Clarifications Q2.

## Decision: Tile `1-9` / `Enter` Routing to Input Mode

**Decision**: Modify `tile.sh` so that `1-9` (or `Enter` on the j/k-selected tile) writes the selected session id to the existing Navigator selection state file (the file currently written by `set_nav_selected`), then `exec`s back into the Navigator's view-focus pane (the right-pane input mode). The user lands directly at the Claude input prompt for the selected session, with all other Navigator state preserved.

**Rationale**: The right pane's nested-tmux input mode already exists and works (it's what `i` triggers from the list). Reusing it from Tile is purely a state-transition change — no new input mechanism is introduced. This keeps the implementation surface tiny.

**Alternatives considered**:
- Implement a separate Tile-side input pipe — rejected; introduces a parallel input path and breaks Constitution V.
- Open a fresh tmux popup pointed at the session — rejected; loses the seamless Navigator return path needed by FR-009a.

## Decision: Escape Return Path

**Decision**: Per Clarifications Q4, Escape from input mode always returns to the Navigator list. The right-pane's `view-focus.conf` already binds `Escape` to `detach-client`, which surfaces back to Navigator. No code change needed — the existing behavior is consistent with the Clarification.

**Rationale**: The current code already returns to the Navigator list view on Escape. The clarification documents what the implementation already does, removing ambiguity for future maintainers.

**Alternatives considered**:
- Caller-context preservation (return to Tile if launched from Tile) — initially recommended but user explicitly chose Option B (always list).

## Decision: Tile Auto-Refresh Mechanism

**Decision**: Remove the `r` key handler from `tile.sh`. Wrap the existing tile-render loop in a `while true; read -rsn1 -t "$REFRESH_INTERVAL" key; do ... done` pattern that mirrors `navigator-list.sh`. On timeout, rebuild and re-render; on key, dispatch.

**Rationale**: Matches Navigator's exact pattern (Clarifications Q5). Single shared mental model. No new timer or background process.

**Alternatives considered**:
- A separate background refresh process — rejected as more complex with no observable benefit at 2s cadence.

## Decision: Test Strategy for New Keys

**Decision**: Add bats integration tests under `tests/integration/`:

1. `test_navigator_new_key.bats` — Simulates `n` in Navigator, verifies session created.
2. `test_navigator_delete_key.bats` — Simulates `d` + `y`, verifies session removed.
3. `test_navigator_digit_jump.bats` — Verifies `1`–`9` jump and out-of-range no-op.
4. `test_tile_input_routing.bats` — Verifies Tile `1` lands in input mode for session #1.

All tests follow the existing socket-isolation pattern (`CLAUDE_TOWER_SESSION_SOCKET` + `TMUX_TMPDIR` before `source_common`) per CLAUDE.md.

**Rationale**: Bats integration tests with socket isolation is the project's standard pattern (Constitution III).

**Alternatives considered**: Unit tests of individual handler functions — useful but insufficient (interactive flow must be end-to-end verifiable).

## Decision: CLI Removal Strategy

**Decision**:
- `bin/tower`: delete the `tile)` case and the `restore` case's id-handling arm; `restore` accepts only `--all` or no arg.
- Help text: update to remove documented `tower tile` and `tower restore <id>` lines.
- README: update CLI table.

**Rationale**: Surgical edits; no compatibility shim needed since both forms are internal-only entry points.

**Alternatives considered**:
- Print a deprecation warning for one release before removal — rejected; the user explicitly wants minimal surface and these are interactive commands (users will notice immediately).

## Open Risks

| Risk | Mitigation |
|---|---|
| Tile→input transition leaves an orphan tmux pane | Test explicitly; rely on existing detach-client cleanup. |
| `read -e` editing doesn't work in all terminal emulators | Fall back to plain `read` if `-e` unavailable; the spec does not mandate readline features. |
| Removing `cleanup.sh` strands users who relied on it | The script was never wired into `bin/tower`; removal is invisible to users. Document in CHANGELOG. |
| Sidebar removal breaks user tmux configs that bind it | Spec FR-014 makes the binding a no-op; document in README upgrade notes. |

## Conclusion

All Phase 0 unknowns resolved. The implementation is a refactor with two new key handlers (`n`, `d`, digit jumps) and one routing change (Tile → input mode). No new external dependencies, no schema changes, no protocol changes.
