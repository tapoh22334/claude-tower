# Feature Specification: Claude Tower Simplification

**Feature Branch**: `003-simplify`
**Created**: 2026-06-03
**Status**: Draft
**Supersedes**: `002-multi-agent-support` (the multi-agent direction is abandoned in favor of staying Claude-only and reducing scope)
**Input**: User description: "claude のセッションを管理するだけのシンプルな形に再設計したい。本体はシンプルなファイル管理とビューを持つプラグインにしたい。"

## Clarifications

### Session 2026-06-03

- Q: How should Navigator's `n` (new session) collect the directory path and optional name? → A: Inline single-line prompt at the bottom of Navigator, prefilled with the caller's CWD. Enter confirms; the prefilled path can be edited. Session name is optional and auto-generated from the directory basename when omitted (same rule as `tower add`).
- Q: How should Navigator's `d` (delete) confirm the destructive action? → A: Inline `Delete '<name>'? [y/N]` prompt at the bottom of Navigator. `y` deletes, any other key cancels. Applies uniformly to active and dormant sessions. No force-delete shortcut in Navigator; CLI `tower rm -f` remains for automation.
- Q: How should the `1-9` direct-jump keys behave when more than 9 sessions exist? → A: `1-9` map only to the first 9 sessions in list order. Sessions beyond #9 are reached via `j/k` or `G`. No multi-digit input, no pagination semantics on number keys.
- Q: When the user enters input mode from Tile (via `1-9` / Enter) and then presses Escape, where should they return? → A: Always return to the Navigator list, regardless of whether input mode was entered from Tile or from the list. Consistency is prioritized over caller-context preservation; the list becomes the single canonical "home" after input mode exit. Users who want to return to Tile press `Tab` from the list.
- Q: At what cadence should Tile auto-refresh? → A: Use the same refresh interval as Navigator (the existing `REFRESH_INTERVAL`, approximately 2 seconds). Sharing the cadence keeps implementation uniform and matches user expectation of equal responsiveness across views.

### Session 2026-06-07 (Tile View redesign)

- Q: The original Tile View used a self-rendered grid of capture-pane snapshots. After in-use testing this proved poor: snapshots lag behind live output, layout was fixed (2 cols, 6 max), and the custom key handling fought with tmux conventions. Replace with what? → A: Use native tmux split-window. The `tower-tile` window contains one pane per active tower session, each running a nested `tmux attach-session` to that session. The `tiled` layout arranges panes automatically and tmux handles resize. This supersedes FR-006/-007/-008/-009/-009a below.
- Q: What happens to dormant sessions in the new Tile? → A: Excluded. Tile View is now defined as a live-monitoring dashboard for active sessions only. Dormant sessions are managed from the Navigator list (where `r` restores them).
- Q: How does the user navigate between tiles? → A: Native tmux pane focus. `prefix + arrow`, `prefix + o`, and mouse click all work as users already expect from tmux. Typing into a focused tile sends the keys straight to that session's Claude.
- Q: How does the user exit Tile? → A: `prefix + t` (the return-to-caller binding installed on the Session server). The Tile-specific `Tab`-back-to-list and `1-9`/`Enter`-to-input-mode keys from US2 are obsoleted.

## Background

Claude Code now provides its own worktree management (`claude wt`), eliminating the need for Tower to manage worktrees or generalize to multiple agents. Tower's enduring value is being a **viewer and switcher** for multiple running Claude sessions inside tmux. The redesign focuses Tower on this single purpose: simple metadata storage plus interactive views (Navigator and Tile).

The user's primary workflows are:

1. **Switch between sessions during work** (Navigator-centric)
2. **Monitor multiple sessions in parallel** (Tile-centric)

Crucially, the Claude usage pattern is "type one command, leave it running, come back later", which makes the Navigator's right-pane input mode (`i`) the dominant interaction — not full attach (`Enter`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Complete Session Management Inside Navigator (Priority: P1)

A user opens the Navigator with `prefix + t` to switch between Claude sessions. While there, they can also create new sessions, delete unwanted ones, and jump directly to a session by number — without leaving Navigator to drop into the shell.

**Why this priority**: This is the core workflow. The current v2 design forced users to exit Navigator to run `tower add` / `tower rm` from the shell, breaking the "switch between sessions" flow. Bringing these back into Navigator makes it self-contained.

**Independent Test**: Open Navigator, press `n` to create a session for a chosen directory, press `d` to delete an existing session (with confirmation), press `3` to jump to the third session — all without exiting Navigator.

**Acceptance Scenarios**:

1. **Given** Navigator is open, **When** the user presses `n` and provides a directory path, **Then** a new session is created and added to the list.
2. **Given** Navigator is open with a session selected, **When** the user presses `d` and confirms, **Then** the session is removed and the list refreshes.
3. **Given** Navigator is open with multiple sessions, **When** the user presses a digit `1`–`9`, **Then** the selection jumps directly to the Nth session.
4. **Given** Navigator is open, **When** the user presses `i` on a session, **Then** the right pane becomes an input target for that session, while the list remains visible.
5. **Given** Navigator is open, **When** the user presses `Enter` on a session, **Then** the user is fully attached to that session's tmux (useful for opening ad-hoc panes).

---

### User Story 2 - Tile View as a Live Monitoring Dashboard (Priority: P2)

A user fires several Claude sessions running long tasks and switches to Tile view to monitor them all at once. When something interesting appears in one tile, they jump directly into input mode for that session with a single key — no detour through the list view.

**Why this priority**: This realizes use case (d). The current Tile makes `1`–`9` return to the list, requiring an extra step to start interacting. Direct routing to input mode matches the "monitor, then poke" usage pattern.

**Independent Test**: Open Tile view from Navigator (`Tab`), observe several running sessions, press `3` (or `Enter` on the selected tile) — the user lands directly in input mode for that session.

**Acceptance Scenarios**:

1. **Given** Tile view is open, **When** the user presses a digit `1`–`9`, **Then** the user lands in Navigator's input mode (`i`) for the corresponding session.
2. **Given** Tile view is open with a tile selected via j/k, **When** the user presses `Enter`, **Then** the user lands in input mode for the selected session.
3. **Given** Tile view is open, **When** the user presses `Tab`, **Then** the view returns to the Navigator list (no input mode entry).
4. **Given** Tile view is open, **When** sessions produce new output, **Then** the tiles refresh automatically (no manual refresh key required).

---

### User Story 3 - Minimal, Predictable Feature Surface (Priority: P3)

A user reading the help, configuration, or source code finds a small, coherent set of features: CLI for scripting (`add`/`rm`/`list`/`restore --all`), two interactive views (Navigator, Tile), and an ambient Statusline. No half-implemented sidebars, no dead key bindings, no commands that duplicate other commands.

**Why this priority**: Reducing scope reduces cognitive load for users and contributors. The current codebase has unused scripts, deprecated entry points, and an unused Sidebar — these create confusion about what Tower actually does.

**Independent Test**: Run `tower help`, read the Navigator help (`?`), and inspect `tmux-plugin/scripts/` — every listed feature is actually implemented and reachable; every script is actually called from somewhere.

**Acceptance Scenarios**:

1. **Given** the Tower help text, **When** the user enumerates commands and keys, **Then** every command corresponds to a working code path with no "deprecated" or "future" placeholders.
2. **Given** the `tmux-plugin/scripts/` directory, **When** a maintainer audits cross-references, **Then** every script is invoked from `bin/tower`, another script, or a tmux key binding.
3. **Given** a fresh install, **When** the user reads `README.md` and `tower help`, **Then** the documented surface matches the actual implementation (no documented features that no longer exist).

---

### Edge Cases

- What happens when the user presses `n` in Navigator with no input given? The new-session prompt is cancelled and Navigator returns to the list unchanged.
- What happens when the user presses `d` on the only remaining session? Confirmation proceeds as normal; the list becomes empty after deletion.
- What happens when the user presses a digit greater than the number of sessions (e.g., `7` with 3 sessions)? The press is ignored.
- What happens to existing pre-redesign sessions and metadata? They continue to work; no migration is required.
- What happens to users who had Sidebar enabled? On upgrade, the Sidebar key binding silently becomes a no-op; users can remove the option from their tmux config.

## Requirements *(mandatory)*

### Functional Requirements — Navigator

- **FR-001**: Navigator MUST support `n` to create a new session. Pressing `n` displays an inline single-line prompt at the bottom of Navigator, prefilled with the caller's current working directory. The user edits the path as needed and presses Enter to confirm; an empty input or Escape cancels. The session name is auto-generated from the directory basename (same rule as `tower add`); custom-name input is not required from Navigator (CLI `tower add -n <name>` remains for that case).
- **FR-002**: Navigator MUST support `d` to delete the selected session (active or dormant). Pressing `d` displays an inline confirmation prompt `Delete '<name>'? [y/N]` at the bottom of Navigator; only `y` proceeds with deletion, any other key cancels. No force-delete shortcut is available from Navigator; CLI `tower rm -f` is retained for automation.
- **FR-003**: Navigator MUST support digit keys `1`–`9` to jump directly to the Nth session in the current list (1-indexed). When fewer than N sessions exist, the press is ignored. When more than 9 sessions exist, only the first 9 are reachable via digit keys; sessions beyond that are reached via `j/k` or `g/G`. No multi-digit input.
- **FR-004**: Navigator MUST retain existing keys: `j/k`, `g/G`, `Enter` (full attach), `i` (input mode), `r`/`R` (restore), `Tab` (Tile), `?` (help), `q` (quit).
- **FR-005**: Navigator help text (`?`) MUST list exactly the keys implemented — no placeholders, no removed-key references.

### Functional Requirements — Tile View

- **FR-006**: Tile view MUST route digit keys `1`–`9` directly to Navigator's input mode (`i`) for the selected session, instead of returning to the list.
- **FR-007**: Tile view MUST route `Enter` on the selected tile to Navigator's input mode for that session.
- **FR-008**: Tile view MUST refresh automatically at the same cadence as Navigator (the existing `REFRESH_INTERVAL`, approximately 2 seconds). The manual refresh key (`r`) MUST be removed.
- **FR-009**: Tile view MUST retain `Tab` to return to the Navigator list view without entering input mode.
- **FR-009a**: Exiting input mode (via Escape) MUST always return the user to the Navigator list, regardless of whether input mode was entered from the list (`i`) or from Tile (`1-9` / `Enter`). The Navigator list is the single canonical "home" after input mode exit. Users returning to Tile press `Tab` from the list.

### Functional Requirements — CLI

- **FR-010**: `tower` (no arguments) MUST launch Navigator.
- **FR-011**: `tower add <path> [-n name]`, `tower rm <name> [-f]`, `tower list`, `tower restore --all` MUST be retained.
- **FR-012**: The `tower tile` CLI MUST be removed (Tile is reachable via Navigator `Tab`).
- **FR-013**: Individual `tower restore <session_id>` MUST be removed; only `tower restore --all` and auto-restore-on-plugin-load remain.

### Functional Requirements — Removed Features

- **FR-014**: The Sidebar feature (`scripts/sidebar.sh` plus its tmux binding and supporting `new-session.sh`) MUST be removed entirely.
- **FR-015**: Dead scripts MUST be removed: `tree-view.sh`, `help.sh`, `diff.sh`, `kill.sh`, `rename.sh`, `input.sh`, `preview.sh`, `session-new.sh` (deprecated), `cleanup.sh` (orphaned).
- **FR-016**: Creation of `~/.claude-tower/worktrees/` directory in `claude-tower.tmux` MUST be removed; Tower does not manage worktrees.
- **FR-017**: Any residual v1 worktree branches inside `session-add.sh`, `session-restore.sh`, or `lib/common.sh` MUST be removed.

### Functional Requirements — Compatibility

- **FR-018**: Existing session metadata files (`~/.claude-tower/metadata/*.meta`) MUST continue to work without migration.
- **FR-019**: Existing keys (`j/k/g/G/Enter/i/r/R/Tab/?/q`) MUST retain their current meanings; only additions (`n/d/1-9`) and Tile changes (`1-9`/`Enter` route to input) are introduced.
- **FR-020**: The Statusline MUST continue to function unchanged.

### Key Entities

- **Session**: A directory path tied to a tmux session running `claude` (or `claude --continue` when restored). Persisted as a metadata file.
- **Session Metadata**: Per-session record on disk identifying the directory and session name. No schema change in this feature.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can complete the full session lifecycle (create → switch → input commands → delete) without leaving Navigator. Zero `tower add` / `tower rm` shell invocations required for the primary workflow.
- **SC-002**: From Tile view, reaching input mode for any visible session is a single key press (`1`–`9` or `Enter`).
- **SC-003**: The number of files under `tmux-plugin/scripts/` is reduced by approximately 50% (from ~19 to ~9 scripts).
- **SC-004**: 100% of pre-redesign sessions and metadata continue to function with no migration.
- **SC-005**: Every key in Navigator help and every command in `tower help` corresponds to working code (no documented-but-missing features, no dead bindings).

## Assumptions

- The user's primary tmux setup keeps `prefix + t` as the Navigator entry point.
- Claude sessions are the only managed program; the multi-agent direction from 002 is abandoned.
- Claude Code's official worktree feature (`claude wt`) is the canonical way to manage worktrees; Tower does not duplicate this.
- The Statusline is a passive display and does not need a redesign.
- The user is willing to accept a one-time tmux config cleanup (removing any Sidebar-related options they may have set).

## Scope

### In Scope

- Adding `n`, `d`, `1`–`9` keys to Navigator
- Changing Tile `1`–`9` / `Enter` to route directly to input mode
- Removing manual refresh from Tile
- Removing `tower tile` and individual `tower restore <id>` CLI commands
- Removing Sidebar feature entirely
- Removing dead/deprecated scripts
- Removing residual worktree references (directory creation, code branches)
- Updating help text and README to match the new surface

### Out of Scope

- Multi-agent support (abandoned; spec 002 is superseded by this one)
- Worktree creation or management
- Session-list filter/search (deferred; not requested)
- Metadata schema changes
- Statusline redesign
- Renaming the project or the `tower` command
- Per-user migration tooling (none needed; backward compatible)

## Notes on Supersession of 002

The `002-multi-agent-support` specification is abandoned. The conclusion from the design discussion: rather than generalizing Tower to manage multiple AI agents, Tower should narrow to "Claude session viewer". The 002 spec directory is left in place for historical reference but no implementation work should proceed against it.
