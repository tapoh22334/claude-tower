# Implementation Plan: Claude Tower Simplification

**Branch**: `003-simplify` (note: working on `002-multi-agent-support` git branch; spec dir is canonical) | **Date**: 2026-06-03 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/mnt/d/working/claude-tower/specs/003-simplify/spec.md`

## Summary

Narrow Claude Tower to a Claude-session-only viewer/switcher. The change has three threads: (1) delete dead/duplicated code (Sidebar, 9 orphan scripts, residual worktree references); (2) bring session management back into Navigator (`n` add, `d` delete, `1-9` jump); (3) make Tile a direct-action monitoring dashboard (`1-9` / `Enter` route into Navigator input mode; Escape always returns to Navigator list; auto-refresh at Navigator's existing cadence). No data model changes; full backward compatibility for existing metadata.

## Technical Context

**Language/Version**: Bash 4.0+ (POSIX-compatible shell scripts)
**Primary Dependencies**: tmux 3.2+, git (optional, only when user invokes from a git repo)
**Storage**: File-based metadata at `~/.claude-tower/metadata/*.meta` (no schema change)
**Testing**: bats (Bash Automated Testing System), submodule at `tests/bats/`
**Target Platform**: Linux, macOS (tested via Docker on CI)
**Project Type**: Single tmux plugin (no frontend/backend split)
**Performance Goals**: CLI response < 100ms (constitution V); Tile/Navigator refresh interval ≈ 2s (existing `REFRESH_INTERVAL`)
**Constraints**: ShellCheck compliant (exclude SC2034, SC1091, SC2317); shfmt 4-space indent; files < 500 lines (constitution V); zero new runtime dependencies
**Scale/Scope**: Expected 1–20 sessions per user; ~9 scripts post-refactor (down from ~19); ~20 FRs

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Verdict | Notes |
|---|---|---|
| I. Session-Only Responsibility | **PASS** | This feature actively reinforces the principle by removing residual worktree directory creation (FR-016) and v1 worktree code branches (FR-017). |
| II. Zero External Dependencies | **PASS** | No new dependencies; pure Bash + tmux changes only. |
| III. Test-First Development | **PASS (planned)** | New key bindings (`n`/`d`/`1-9`, Tile routing) MUST have bats tests written before implementation. Existing tests must keep passing. |
| IV. Backward Compatibility | **PASS** | FR-018, FR-019, FR-020 explicit. Metadata format unchanged; v1 worktree fields are read but no longer written by load_metadata (already current behavior). |
| V. Simplicity and Performance | **PASS** | Net file reduction ~50%. No new perf-sensitive code paths. Refresh interval unchanged. |

**No violations**. Complexity Tracking section is empty (omitted).

## Project Structure

### Documentation (this feature)

```text
specs/003-simplify/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output (minimal — no schema change)
├── quickstart.md        # Phase 1 output (manual verification steps)
├── contracts/
│   └── tower-cli.md     # CLI surface contract (additions/removals)
├── checklists/
│   └── requirements.md  # Already exists from /speckit.specify
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
tmux-plugin/
├── claude-tower.tmux              # MODIFY: remove worktrees mkdir, remove any Sidebar bindings
├── bin/
│   └── tower                      # MODIFY: remove 'tile' subcommand; restrict 'restore' to --all only
├── conf/
│   └── view-focus.conf            # KEEP: used by Navigator nested tmux
├── lib/
│   ├── common.sh                  # MODIFY: audit/remove v1 worktree compat branches if present
│   └── error-recovery.sh          # KEEP
└── scripts/
    ├── navigator.sh               # KEEP
    ├── navigator-list.sh          # MODIFY: add `n`, `d`, `1-9` key handlers; update footer/help text
    ├── navigator-view.sh          # KEEP (input mode lives here)
    ├── tile.sh                    # MODIFY: route 1-9/Enter to input mode; remove `r`; ensure auto-refresh
    ├── session-add.sh             # MODIFY: remove v1 worktree branches if present
    ├── session-delete.sh          # KEEP
    ├── session-list.sh            # KEEP
    ├── session-restore.sh         # MODIFY: ensure no v1 worktree branches; --all and auto-restore only
    └── statusline.sh              # KEEP
    # DELETED:
    #   sidebar.sh, new-session.sh, tree-view.sh, help.sh, diff.sh,
    #   kill.sh, rename.sh, input.sh, preview.sh, session-new.sh, cleanup.sh

tests/
├── integration/                   # MODIFY: add bats tests for n/d/1-9, Tile routing
├── e2e/                           # MODIFY: end-to-end keyflow for Navigator self-sufficiency
└── scenarios/                     # KEEP

README.md                          # MODIFY: remove Sidebar section, update key reference, update CLI table
```

**Structure Decision**: Existing single-project tmux-plugin layout is retained. This refactor operates entirely within `tmux-plugin/` and `tests/`. No new directories created.

## Phase 0 — Research

See [research.md](./research.md). All decisions captured. No `NEEDS CLARIFICATION` items remain (Clarifications session 2026-06-03 resolved all UX ambiguity).

## Phase 1 — Design & Contracts

- [data-model.md](./data-model.md) — Existing Session/Metadata entities documented; no field changes.
- [contracts/tower-cli.md](./contracts/tower-cli.md) — Final CLI surface; removed commands explicitly listed.
- [quickstart.md](./quickstart.md) — Manual verification script for a reviewer.

## Post-Design Constitution Re-check

| Principle | Status |
|---|---|
| I. Session-Only Responsibility | **PASS** — Reinforced. |
| II. Zero External Dependencies | **PASS** — No additions. |
| III. Test-First Development | **PASS** — Test plan present in tasks.md (next phase). |
| IV. Backward Compatibility | **PASS** — Metadata load path unchanged; v1 fields still readable. |
| V. Simplicity and Performance | **PASS** — Net simplification. |

No violations. Proceed to `/speckit.tasks`.

## Complexity Tracking

*(empty — no constitution violations to justify)*
