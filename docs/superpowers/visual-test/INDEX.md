# Visual verification captures (Docker + real tmux)

These are raw `tmux capture-pane -p` (ANSI stripped) screenshots of the
Navigator UI, taken inside the `claude-tower-test` Docker image against a
real tmux server — not unit-test assertions on internal functions. They are
the visual-verification record for the 5-state Navigator redesign
(`docs/superpowers/specs/2026-07-11-tower-session-registry-design.md`).

Scenario: 5 sessions were registered, one per state (`busy`/`active`/
`dormant`/`dead`/`lost`), by controlling `CLAUDE_PROJECTS_DIR` fixture jsonl
mtimes and deleting a cwd directory, then a real `navigator-list.sh` was
launched in a tmux pane and driven with real key presses (`?`, `j`, `j`).
Reproduce with the driver used to generate these:
`tests/integration/test_display_snapshot.bats` exercises the same
`render_navigator_list` pattern per-test; see that file for the fixture
helpers (`create_mock_jsonl`, `create_mock_metadata`).

## 01_list_view_all_states.txt

The Navigator list pane with one session in each of the 5 states:

- `● webapp (webapp)` — busy (jsonl touched within `TOWER_BUSY_WINDOW`)
- `▶ api-server (api-server)` — active (tmux session up, jsonl stale)
- `○ docs-site (docs-site)` — dormant (no tmux, jsonl + cwd both present)
- `── unrecoverable ──` separator, then:
- `✗ deleted-repo (deleted-repo)` — dead (cwd directory deleted)
- `? eeeeeee (old-experiment)` — lost (metadata only, no jsonl at all)

Look for: correct icon per state, cwd-basename labels (not raw session
IDs), `(name)` suffix from the registry's optional `session_name`, the
dim `── unrecoverable ──` separator appearing exactly once before the
dead/lost block, and the current footer
`j/k:nav Enter:attach i:input n:add D:del r:resume q:quit` (no `R`
restore-all — that key was removed by the redesign).

## 02_help_screen.txt

The `?` help screen. Look for: no mention of `R` (restore-all) as a
single-key binding — only `r  Resume selected dormant session` — and the
`n` binding text now describing the unified add/new flow
("pick existing Claude session or start new").

## 03_list_view_selection_moved.txt

The list view after dismissing the help screen (space) and pressing `j`
twice. Look for: a **clean** redraw with no leftover text from the
help screen. This capture was the reproduction case for a real bug found
by this Docker testing pass — `render_list()` printed each row followed by
a bare `\n`, so a line left over from the taller help screen (drawn via
`clear`, not `render_list`) that fell after the end of the new frame's
content was never erased; `\n` moves the cursor down without clearing the
row's existing characters. Fixed in `navigator-list.sh` by appending
`\033[K` (clear-to-end-of-line) to every line before the newline. This
capture is post-fix and shows no artifacts; the raw before/after terminal
output that demonstrated the bug is in the docker-visual-report (not
committed, since it's reproducible from the bug description).

## 04_tile_view.txt

The Tile view (`Tab` from the list), showing all 4 tmux-backed sessions in
a grid with per-tile state icons. This capture was also the reproduction
case for a second real bug: `tile.sh`'s `draw_tiles()` ended its per-session
loop with `[[ $idx -ge 6 ]] && break`, whose exit status is 1 whenever the
condition is false (i.e., whenever there are fewer than 6 tiles — the
common case). Because `tile.sh` runs under `set -euo pipefail` and `main()`
calls `draw_tiles` unguarded, this silently killed the whole Tile view
right after drawing its first frame, before it ever read a keypress — Tile
view was effectively unusable for < 6 sessions. Fixed by rewriting the
check as `if [[ $idx -ge 6 ]]; then break; fi`, which cannot leak a
nonzero status. This capture is post-fix: the process stays alive and
keeps drawing (dormant/dead sessions currently all show the generic
"Dormant - Press 'r' to restore" caption — tile.sh only distinguishes
dormant-vs-not, a pre-existing UX nuance from before the 5-state redesign
that is not fixed here; see report for the provisional ruling to defer it).

## Reproducing

```
docker build -f Dockerfile.test -t claude-tower-test .
docker run --rm claude-tower-test              # unit + integration suites
make test-docker                                 # same, via the Makefile target
```

The scenario driver script used to produce these captures is not checked
into the repo (it was a throwaway harness in the agent's scratchpad); the
fixture-construction technique is preserved in
`tests/integration/test_display_snapshot.bats`.
