# Phase 1 Data Model: Simplification

**Date**: 2026-06-03
**Feature**: 003-simplify
**Status**: No schema changes in this feature.

This document is included for completeness per the `/speckit.plan` template. The feature does not change any persisted data structures.

## Entities (unchanged)

### Session

A directory path tied to a tmux session running `claude` (or `claude --continue` when restored).

| Field | Type | Source | Notes |
|---|---|---|---|
| session_id | string | tmux | tmux session name (e.g., `tower-myproject`) |
| name | string | user / derived | Short label; defaults to directory basename |
| directory_path | string (path) | metadata | Absolute path the Claude process runs in |
| state | enum | runtime | `active` (tmux session exists) or `dormant` (only metadata exists) |
| program | string | constant | `claude` (always; multi-agent direction abandoned) |

### Session Metadata (file at `~/.claude-tower/metadata/<session_id>.meta`)

Existing key=value text file. **No new fields**. **No deprecated fields removed** (v1 fields stay readable for backward compatibility per FR-018 and Constitution IV).

```text
session_id=<tmux session name>
name=<short label>
directory_path=<absolute path>
# v1 compatibility (read-only — no longer written):
# worktree_path=...
# repository_path=...
```

`load_metadata()` resolution priority (unchanged):
1. `directory_path` (v2)
2. `worktree_path` (v1 fallback)
3. `repository_path` (v1 fallback)

## State Transitions (unchanged)

```text
[Created via tower add or Navigator 'n']
            │
            ▼
        active ──(tmux server killed)──▶ dormant
            ▲                                 │
            └────(tower restore --all)────────┘
            │
            ▼
        [Deleted via tower rm or Navigator 'd']
```

## Affected by 003 (none structurally)

This feature changes **how** sessions are created/deleted (Navigator keys vs CLI), but the entity shape and lifecycle are identical to the pre-redesign state.
