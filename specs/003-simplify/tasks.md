# Tasks: Claude Tower Simplification

**Input**: Design documents from `/specs/003-simplify/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/tower-cli.md ✓, quickstart.md ✓

**Tests**: REQUIRED by Constitution III (Test-First Development). Integration tests use bats with socket isolation pattern per CLAUDE.md.

**Organization**: Tasks grouped by user story (US1, US2, US3) so each story is independently testable and deliverable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Parallelizable (different files, no in-phase dependencies)
- **[Story]**: US1, US2, US3 — maps to spec.md user stories
- All paths are absolute

---

## Phase 1: Setup

**Purpose**: Verify environment; no new dependencies introduced.

- [x] T001 Verify bats submodule present and executable at `/mnt/d/working/claude-tower/tests/bats/bin/bats`; if missing, run `git submodule update --init tests/bats`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Capture data US1's `n` key needs (caller CWD). MUST complete before US1.

**⚠️ CRITICAL**: US1 cannot proceed until T002 is complete.

- [x] T002 Extend `tmux-plugin/claude-tower.tmux` Navigator launch binding to additionally write `#{pane_current_path}` to `/tmp/claude-tower/caller-cwd` alongside the existing `caller` file (modify the `run-shell -b` arg in the `tmux bind-key` call)

**Checkpoint**: Foundation ready. User stories can now begin.

---

## Phase 3: User Story 1 — Navigator Self-Sufficiency (Priority: P1) 🎯 MVP

**Goal**: Navigator supports full session lifecycle (`n` add, `d` delete, `1-9` jump) without dropping to the shell.

**Independent Test**: Open Navigator → press `n` → Enter → new session appears. Press `d` → `y` → session removed. Press `3` → selection jumps. All without `q` / shell.

### Tests for US1 (write FIRST, ensure FAIL before implementation)

- [x] T003 [P] [US1] Write integration test `/mnt/d/working/claude-tower/tests/integration/test_navigator_new_key.bats` — simulates `n` keystroke + path input; asserts metadata file and tmux session created. Follow socket-isolation pattern (`CLAUDE_TOWER_SESSION_SOCKET` + `TMUX_TMPDIR` before `source_common`).
- [x] T004 [P] [US1] Write integration test `/mnt/d/working/claude-tower/tests/integration/test_navigator_delete_key.bats` — pre-creates a session, simulates `d` + `y`; asserts metadata and tmux session removed. Also covers `d` + `n` (cancel) leaves session intact.
- [x] T005 [P] [US1] Write integration test `/mnt/d/working/claude-tower/tests/integration/test_navigator_digit_jump.bats` — pre-creates 3 sessions, simulates `1`/`2`/`3` to verify selection; simulates `7` (out of range) to verify no-op.

### Implementation for US1

- [x] T006 [US1] Add `_load_caller_cwd()` helper in `/mnt/d/working/claude-tower/tmux-plugin/scripts/navigator-list.sh` — reads `/tmp/claude-tower/caller-cwd`, defaults to `$HOME` if missing/empty
- [x] T007 [US1] Add `_prompt_inline()` helper in `/mnt/d/working/claude-tower/tmux-plugin/scripts/navigator-list.sh` — renders a single-line prompt at the bottom of the pane (using ANSI cursor positioning), reads input via `read -e -i "$default"`, returns the value (or empty on cancel)
- [x] T008 [US1] Add `add_new_session()` action in `/mnt/d/working/claude-tower/tmux-plugin/scripts/navigator-list.sh` — calls `_prompt_inline` with caller CWD as default; on non-empty result, invokes `"$SCRIPT_DIR/session-add.sh" "$path"`; rebuilds list afterward
- [x] T009 [US1] Add `delete_selected_session()` action in `/mnt/d/working/claude-tower/tmux-plugin/scripts/navigator-list.sh` — gets selected session name; renders `Delete '<name>'? [y/N]` via `_prompt_inline`-style single-char read; on `y`, invokes `"$SCRIPT_DIR/session-delete.sh" "$name" -f`; rebuilds list afterward
- [x] T010 [US1] Add `jump_to_index()` action in `/mnt/d/working/claude-tower/tmux-plugin/scripts/navigator-list.sh` — takes digit `1`–`9`, validates `(digit-1) < ${#SESSION_IDS[@]}`, sets `selected_index` accordingly, calls `set_nav_selected`
- [x] T011 [US1] Wire `n`, `d`, and `1`–`9` cases into the `case "$key"` switch in `main_loop` of `/mnt/d/working/claude-tower/tmux-plugin/scripts/navigator-list.sh`
- [x] T012 [US1] Update footer keybindings line in `build_session_list_display` (around line 175) of `/mnt/d/working/claude-tower/tmux-plugin/scripts/navigator-list.sh` to: `j/k:nav  Enter:attach  i:input  n:new  d:del  1-9:jump  r:restore  ?:help  q:quit`
- [x] T013 [US1] Update `show_help()` in `/mnt/d/working/claude-tower/tmux-plugin/scripts/navigator-list.sh` to list `n`, `d`, and `1`–`9` under Actions; remove the "Session Management (CLI): tower add/rm" hint (no longer needed)

**Checkpoint**: T003–T005 pass with the implementation from T006–T013. User Story 1 fully functional.

---

## Phase 4: User Story 2 — Tile View Direct Input (Priority: P2)

**Goal**: From Tile, pressing `1`–`9` or `Enter` lands the user directly in input mode for that session. Tile auto-refreshes; `r` is gone.

**Independent Test**: From Navigator press `Tab` → Tile appears. Wait 2s → tiles refresh on their own. Press `2` → input mode for session #2. Type text → it reaches Claude. Press Escape → back to Navigator list.

### Tests for US2

- [x] T014 [P] [US2] Write integration test `/mnt/d/working/claude-tower/tests/integration/test_tile_input_routing.bats` — pre-creates 2 sessions, opens Tile, simulates `1`; asserts that input is routed to session #1 (e.g., by inspecting the right pane's nested-tmux target session via the existing socket-isolation harness).
- [x] T015 [P] [US2] Write integration test `/mnt/d/working/claude-tower/tests/integration/test_tile_auto_refresh.bats` — opens Tile, modifies session state externally, waits one `REFRESH_INTERVAL` + buffer, asserts tile content updated without any key press. Also verifies `r` keystroke is a no-op (does not trigger a forced refresh / does not throw).

### Implementation for US2

- [x] T016 [US2] Refactor `tile.sh` main input loop in `/mnt/d/working/claude-tower/tmux-plugin/scripts/tile.sh` to use timed read pattern `read -rsn1 -t "$REFRESH_INTERVAL" key` mirroring `navigator-list.sh:527-528`; on timeout rebuild + re-render; on key, dispatch via the existing case switch
- [x] T017 [US2] Modify the `1-9` case in `tile.sh` to: (a) set the chosen session via `set_nav_selected`; (b) signal entry to input mode (write to whatever IPC mechanism `navigator-view.sh` listens on, or detach the tile process so `navigator.sh` re-enters with the view pane focused — confirm during implementation by reading `navigator.sh` and `navigator-view.sh`); (c) exit the tile loop
- [x] T018 [US2] Modify the `Enter` case in `tile.sh` to use the same input-mode entry path as T017
- [x] T019 [US2] Remove the `r` case from `tile.sh` (manual refresh no longer supported per FR-008)
- [x] T020 [US2] Update the header comment block in `/mnt/d/working/claude-tower/tmux-plugin/scripts/tile.sh` (lines 5-15) to reflect new key bindings: `1-9`/`Enter` → input mode, `Tab` → list, `q/Esc` → quit; remove the `r` line

**Checkpoint**: T014–T015 pass. Tile becomes a live monitoring + direct-action dashboard.

---

## Phase 5: User Story 3 — Minimal Feature Surface (Priority: P3)

**Goal**: Dead code, deprecated entry points, Sidebar feature, and residual worktree references are all gone. Every documented surface matches working code.

**Independent Test**: `ls tmux-plugin/scripts/` shows only the 9 keeper files. `tower help` lists no `tile` or per-id `restore`. `grep -R worktrees tmux-plugin/claude-tower.tmux` is empty.

### Tests for US3

- [x] T021 [P] [US3] Write integration test `/mnt/d/working/claude-tower/tests/integration/test_minimal_surface.bats` — asserts that none of the deleted files (sidebar.sh, new-session.sh, tree-view.sh, help.sh, diff.sh, kill.sh, rename.sh, input.sh, preview.sh, session-new.sh, cleanup.sh) exist under `tmux-plugin/scripts/`
- [x] T022 [P] [US3] Write integration test `/mnt/d/working/claude-tower/tests/integration/test_cli_surface.bats` — asserts `tower tile` exits non-zero with "Unknown command"; asserts `tower restore some-id` either errors OR is treated as `--all` (per contracts/tower-cli.md); asserts `tower help` output does not contain the substring `tile` (as a subcommand line) or a per-id restore example

### Implementation — Delete dead scripts (parallel)

- [x] T023 [P] [US3] Delete `/mnt/d/working/claude-tower/tmux-plugin/scripts/sidebar.sh`
- [x] T024 [P] [US3] Delete `/mnt/d/working/claude-tower/tmux-plugin/scripts/new-session.sh`
- [x] T025 [P] [US3] Delete `/mnt/d/working/claude-tower/tmux-plugin/scripts/tree-view.sh`
- [x] T026 [P] [US3] Delete `/mnt/d/working/claude-tower/tmux-plugin/scripts/help.sh`
- [x] T027 [P] [US3] Delete `/mnt/d/working/claude-tower/tmux-plugin/scripts/diff.sh`
- [x] T028 [P] [US3] Delete `/mnt/d/working/claude-tower/tmux-plugin/scripts/kill.sh`
- [x] T029 [P] [US3] Delete `/mnt/d/working/claude-tower/tmux-plugin/scripts/rename.sh`
- [x] T030 [P] [US3] Delete `/mnt/d/working/claude-tower/tmux-plugin/scripts/input.sh`
- [x] T031 [P] [US3] Delete `/mnt/d/working/claude-tower/tmux-plugin/scripts/preview.sh`
- [x] T032 [P] [US3] Delete `/mnt/d/working/claude-tower/tmux-plugin/scripts/session-new.sh`
- [x] T033 [P] [US3] Delete `/mnt/d/working/claude-tower/tmux-plugin/scripts/cleanup.sh`

### Implementation — Worktree residue removal

- [x] T034 [US3] Remove the `mkdir -p "${CLAUDE_TOWER_WORKTREE_DIR:-$HOME/.claude-tower/worktrees}"` line from `/mnt/d/working/claude-tower/tmux-plugin/claude-tower.tmux` (around line 49); also remove any `CLAUDE_TOWER_WORKTREE_DIR` references
- [x] T035 [US3] Audit `/mnt/d/working/claude-tower/tmux-plugin/lib/common.sh` — remove any `worktree_path` writes (reads must stay for v1 compat per FR-018), remove any helper functions that only serve worktree creation
- [x] T036 [US3] Audit `/mnt/d/working/claude-tower/tmux-plugin/scripts/session-add.sh` — remove any code path that creates or references git worktrees
- [x] T037 [US3] Audit `/mnt/d/working/claude-tower/tmux-plugin/scripts/session-restore.sh` — remove any worktree-specific recovery logic; keep --all and auto-restore-on-load paths

### Implementation — CLI surface trim

- [x] T038 [US3] Remove the `tile)` case from `main()` in `/mnt/d/working/claude-tower/tmux-plugin/bin/tower`
- [x] T039 [US3] Modify the `restore)` case in `/mnt/d/working/claude-tower/tmux-plugin/bin/tower` to call `session-restore.sh --all` regardless of argument; reject per-id form by stripping any session-id arg (or treat as --all and document)
- [x] T040 [US3] Update `show_help()` in `/mnt/d/working/claude-tower/tmux-plugin/bin/tower` — remove the `tile` and `restore [--all]` lines and replace with the contract from `/mnt/d/working/claude-tower/specs/003-simplify/contracts/tower-cli.md`

### Implementation — Documentation

- [x] T041 [US3] Update `/mnt/d/working/claude-tower/README.md` — remove the Sidebar section (and any "Toggle with prefix + C" references)
- [x] T042 [US3] Update `/mnt/d/working/claude-tower/README.md` — add Navigator keys `n`, `d`, `1-9` to the key reference table; remove `tower tile`; show only `tower restore [--all]` form
- [x] T043 [US3] Update `/mnt/d/working/claude-tower/tmux-plugin/README.md` — remove references to deleted scripts (`session-new.sh`, `cleanup.sh`, `sidebar.sh`, `new-session.sh`, etc.) from the file tree

**Checkpoint**: T021–T022 pass. Repo now matches the contract surface.

---

## Phase 6: Polish & Cross-Cutting

- [x] T044 Run `make lint` from `/mnt/d/working/claude-tower/` — fix any ShellCheck violations (exclusions per CLAUDE.md: SC2034, SC1091, SC2317)
- [x] T045 Run `make format-fix` from `/mnt/d/working/claude-tower/` to ensure shfmt compliance
- [x] T046 Run `make test` from `/mnt/d/working/claude-tower/` — all bats tests must pass (including new ones from US1/US2/US3)
- [ ] T047 Manually run `/mnt/d/working/claude-tower/specs/003-simplify/quickstart.md` sections 1–7; confirm Definition of Done
- [x] T048 Verify `git status` matches expected: ~11 deleted files, navigator-list.sh / tile.sh / bin/tower / claude-tower.tmux / README modified, new tests added; nothing unintended

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)**: No deps; can start immediately
- **Foundational (T002)**: Depends on T001; BLOCKS US1
- **US1 (T003–T013)**: Depends on T002; independent of US2 and US3
- **US2 (T014–T020)**: Depends on T001; independent of US1 and US3 (can run in parallel with US1)
- **US3 (T021–T043)**: Depends on T001; mostly independent — script deletions (T023–T033) are safe in any order since the dead scripts have no live callers (verified in research.md). However, T034–T037 (worktree residue) should run after the codebase is audited.
- **Polish (T044–T048)**: Depends on US1 + US2 + US3 completion

### Within Each User Story

- **TDD**: Tests (Txxx[P][USn]) MUST be written and verified FAIL before implementation tasks
- US1: T003–T005 (tests) → T006 → T007 → T008/T009/T010 [P] → T011 → T012 → T013
- US2: T014–T015 (tests) → T016 → T017/T018 → T019 → T020
- US3: T021–T022 (tests) → T023–T033 [P, all parallel] → T034 → T035–T037 [P after T034] → T038 → T039 → T040 → T041–T043 [P]

### Parallel Opportunities

- **All test-writing tasks** within a story marked [P] (T003, T004, T005; T014, T015; T021, T022) can run in parallel
- **Script deletion tasks T023–T033** can all run in parallel (independent file deletions)
- **README update tasks T041–T043** can run in parallel
- **Whole stories US1, US2, US3** can be developed in parallel by separate developers if available, since file overlap is minimal (US1 → navigator-list.sh; US2 → tile.sh; US3 → many different files)

---

## Parallel Example: US1 Tests

```bash
# Launch all three US1 tests for parallel authoring:
Task: "Write tests/integration/test_navigator_new_key.bats per T003"
Task: "Write tests/integration/test_navigator_delete_key.bats per T004"
Task: "Write tests/integration/test_navigator_digit_jump.bats per T005"
```

## Parallel Example: US3 Script Deletions

```bash
# Delete all 11 dead scripts in parallel — no inter-dependency:
rm tmux-plugin/scripts/sidebar.sh         # T023
rm tmux-plugin/scripts/new-session.sh     # T024
rm tmux-plugin/scripts/tree-view.sh       # T025
# ... (T026–T033)
```

---

## Implementation Strategy

### MVP First (US1 only)

1. T001 (Setup)
2. T002 (Foundational)
3. T003–T013 (US1)
4. **STOP and VALIDATE**: User can manage sessions entirely from Navigator
5. Ship as MVP

### Incremental Delivery

1. Setup + Foundational → ready
2. + US1 → Navigator self-sufficient → ship/demo
3. + US2 → Tile becomes a live action dashboard → ship/demo
4. + US3 → Clean surface, minimal docs drift → ship/demo (full feature)

### Parallel Team Strategy

After T002 completes:
- Developer A: US1 (navigator-list.sh)
- Developer B: US2 (tile.sh)
- Developer C: US3 cleanup (mass deletes + CLI + README)
File overlap is near-zero across stories.

---

## Notes

- Total tasks: 48
- Per-story task counts: Setup 1 / Foundational 1 / US1 11 / US2 7 / US3 23 / Polish 5
- Constitution III mandates TDD — tests are not optional; they precede implementation in every story
- T035–T037 (worktree residue audit) may turn out to be no-ops if the v1 code has already been cleaned in 001-tower-v2-simplify; in that case mark complete after grep verification
- T039 (`tower restore` behavior) — per contracts/tower-cli.md, treating any arg as `--all` is acceptable; rejecting is also acceptable. Implementor's choice within contract.
- Commit after each task or each logical task group; never mix story commits
