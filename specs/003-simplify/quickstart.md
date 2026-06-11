# Quickstart — Verifying 003 Simplification

**Feature**: 003-simplify
**Audience**: reviewer / maintainer
**Prerequisites**: Plugin installed (`tmux source-file ~/.tmux.conf` after pulling the branch), tmux 3.2+, Claude CLI available on PATH, ≥ 2 sample directories to use as session targets.

## 1. Confirm dead code is gone

```bash
ls tmux-plugin/scripts/
# Expect EXACTLY these files:
#   navigator.sh navigator-list.sh navigator-view.sh
#   session-add.sh session-delete.sh session-list.sh session-restore.sh
#   tile.sh statusline.sh
# Should NOT contain: sidebar.sh new-session.sh tree-view.sh help.sh diff.sh
#                     kill.sh rename.sh input.sh preview.sh session-new.sh cleanup.sh

grep -R "worktrees" tmux-plugin/claude-tower.tmux
# Expect: no matches
```

## 2. Confirm CLI surface matches contract

```bash
tower help
# Expect: list does NOT include 'tile' subcommand
# Expect: 'restore' line shows only '[--all]', no '<session_id>' form

tower tile 2>&1 | head -3
# Expect: "Error: Unknown command: tile"

tower restore some-bogus-id 2>&1 | head -3
# Expect: error or treated as --all (no per-id restore)
```

## 3. Verify Navigator self-sufficiency (User Story 1)

Inside tmux:

```text
1. cd /path/to/some/project
2. prefix + t                              → Navigator opens
3. Press n                                 → Inline prompt shows, prefilled with current path
4. Press Enter                             → New session created, appears in list
5. Press 3                                 → Selection jumps to 3rd session (if exists)
6. Press 9 (with only 3 sessions present)  → No-op (selection stays at 3)
7. Press d on a session                    → "Delete '<name>'? [y/N]" appears
8. Press y                                 → Session removed, list refreshes
9. Press q                                 → Navigator closes
```

All operations must work without leaving Navigator. No shell drops required for any step.

## 4. Verify Tile direct-input (User Story 2)

Inside tmux (Navigator open, at least 2 sessions):

```text
1. Press Tab                               → Tile view appears
2. Wait 2-3 seconds                        → Tiles auto-refresh (no key needed)
3. Press 1                                 → Land in input mode for session #1 (right pane)
4. Type any text + Enter                   → Text sent to session #1's Claude
5. Press Escape                            → Returns to NAVIGATOR LIST (not Tile)
6. Press Tab                               → Back to Tile to verify Tab still works
7. Use j/k to select tile #2, press Enter  → Land in input mode for session #2
8. Press Escape                            → Returns to Navigator list again
```

The `r` key in Tile must do nothing (no longer bound).

## 5. Verify backward compatibility (User Story 3 / FR-018)

```bash
# Create a v1-style metadata file by hand
cat > ~/.claude-tower/metadata/legacy-test.meta <<'EOF'
session_id=tower-legacy-test
name=legacy-test
worktree_path=/tmp/legacy-test
EOF
mkdir -p /tmp/legacy-test

tower list
# Expect: 'legacy-test' appears in the list with /tmp/legacy-test as its directory
```

## 6. Test suite

```bash
make lint     # Expect: 0 violations
make test     # Expect: all bats tests pass (including new ones for n/d/1-9/Tile routing)
```

## 7. Statusline still works (FR-020)

If the user has `set -g status-right '#(~/.tmux/plugins/claude-tower/tmux-plugin/scripts/statusline.sh)'` in their config:

```text
1. Open tmux                               → Status line shows session counts (active/dormant)
2. Add a session via tower add or Navigator → Counts update on next status interval
```

## Definition of Done

- All seven sections above pass.
- `git status` shows the expected set of modified/deleted files (see plan.md).
- `git diff --stat` shows a net reduction in lines under `tmux-plugin/scripts/`.
- README reflects the new key bindings and the absent Sidebar/`tower tile`.
