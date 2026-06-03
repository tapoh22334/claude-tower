# Feature Specification: Multi-Agent Support

**Feature Branch**: `002-multi-agent-support`
**Created**: 2026-02-19
**Status**: Draft
**Input**: User description: "claude専用になっているので、他のaiエージェントにも対応したい。開始とセッション再開コマンドを指定すれば独自エージェントも起動可能。addするときにエージェントを指定。エージェントなしも指定可能。"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Specify Agent When Adding a Session (Priority: P1)

A user adds a new session and specifies which AI agent to use via `--program`. The agent is launched immediately. If no `--program` is given, the globally configured default is used (which defaults to `claude` for backward compatibility).

**Why this priority**: This is the core interaction. Every session creation must support agent selection. Without this, Tower remains locked to a single agent.

**Independent Test**: Can be fully tested by running `tower add . --program codex` and verifying the session launches `codex` instead of `claude`.

**Acceptance Scenarios**:

1. **Given** a user runs `tower add . --program aider`, **When** the session is created, **Then** the session launches `aider` in the specified directory.
2. **Given** a user runs `tower add .` without `--program`, **When** the session is created, **Then** the session launches the globally configured default agent.
3. **Given** no global default is configured, **When** the user runs `tower add .`, **Then** the session launches `claude` (backward compatible default).
4. **Given** a user runs `tower add . --program aider`, **When** the user views the session list, **Then** the agent name `aider` is displayed alongside the session.

---

### User Story 2 - Add a Shell-Only Session Without an Agent (Priority: P2)

A user wants to add a session that opens a plain shell without launching any AI agent. This is useful for manual tasks, running scripts, or preparing an environment before starting an agent manually.

**Why this priority**: Expands Tower from "AI agent manager" to "session manager". Users can mix AI-assisted and manual sessions in the same Navigator, keeping their workflow unified.

**Independent Test**: Can be tested by running `tower add . --program none` and verifying the session opens a shell prompt without any agent process running.

**Acceptance Scenarios**:

1. **Given** a user runs `tower add . --program none`, **When** the session is created, **Then** the session opens a plain shell in the specified directory without launching any program.
2. **Given** a shell-only session becomes dormant, **When** the user restores it, **Then** the session opens a plain shell again (no agent is launched).
3. **Given** a shell-only session exists, **When** the user views the session list, **Then** the session shows no agent indicator (or shows "shell").

---

### User Story 3 - Custom Start and Resume Commands (Priority: P3)

A user wants to use an AI agent that Tower doesn't know about. By configuring a custom start command and a custom resume command, any CLI-based program can be managed as a Tower session. The start command is used for new sessions; the resume command is used when restoring dormant sessions or restarting.

**Why this priority**: Makes Tower fully extensible. Users are not limited to well-known agents; any CLI program can participate. This depends on P1 being implemented first.

**Independent Test**: Can be tested by configuring a custom start command (e.g., `my-agent start`) and resume command (e.g., `my-agent resume`), creating a session, making it dormant, and restoring it.

**Acceptance Scenarios**:

1. **Given** the user has configured a resume command of `codex --resume`, **When** a dormant session is restored, **Then** the agent launches with `codex --resume` instead of the default `claude --continue`.
2. **Given** no resume command is configured, **When** a dormant session is restored, **Then** the agent launches with `<program> --continue` as the default (backward compatible).
3. **Given** the user has configured an empty resume command, **When** a dormant session is restored, **Then** the session opens a plain shell (same as shell-only mode).

---

### Edge Cases

- What happens when the configured agent command is not found on the system? Tower displays a clear error message indicating which command is missing and suggests checking the installation.
- What happens when a session's per-session agent is uninstalled after the session was created? Tower still attempts to launch the configured command; the shell naturally shows the command-not-found error.
- What happens when the user upgrades from a version without multi-agent support? Existing sessions and metadata continue working with `claude` as the implicit default.
- What happens when the user specifies `--program` with an empty value? Tower rejects the input with a validation error.
- What happens when `--program none` session is restarted? Tower reopens a shell without launching any agent.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST allow users to configure a default AI agent program globally via environment variable.
- **FR-002**: System MUST default to `claude` when no agent is explicitly configured (backward compatibility).
- **FR-003**: System MUST allow users to specify a per-session agent program when adding a new session via `--program <name>`.
- **FR-004**: System MUST support `--program none` to create shell-only sessions that launch no agent program.
- **FR-005**: System MUST persist the per-session agent program in session metadata so it survives restarts and dormant-state recovery.
- **FR-006**: System MUST use the session-specific agent program (if set) over the global default when launching, restoring, or restarting a session.
- **FR-007**: System MUST allow users to configure a custom resume command globally via environment variable, used when restoring dormant sessions or restarting agents.
- **FR-008**: System MUST default to appending `--continue` to the agent program as the resume command when none is explicitly configured (backward compatible with Claude Code).
- **FR-009**: System MUST use generic terminology (e.g., "AI agent", "program") instead of "Claude" in all user-facing runtime messages, help text, and Navigator UI labels. Project branding ("Claude Tower") and documentation remain unchanged.
- **FR-010**: System MUST validate that the `--program` option value is a non-empty string containing only safe characters (alphanumeric, hyphens, underscores, forward slashes), or the special value `none`.
- **FR-011**: System MUST display the configured agent name in the session list and Navigator UI when per-session agents differ from the default.
- **FR-012**: Existing sessions created before this feature MUST continue to work without modification, using `claude` as the implicit program and `--continue` as the implicit resume command.

### Key Entities

- **Agent Configuration**: Represents a start command and resume command for an AI agent. Can be set globally (environment variables) or per-session (stored in metadata). The special value `none` means no agent is launched.
- **Session Metadata** (extended): Adds optional `program` and `resume_command` fields to the existing metadata format. Absence of these fields implies the default values (`claude` and `claude --continue` respectively).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can launch sessions with any CLI-based AI agent within the same number of steps as current Claude-only sessions (one additional `--program` flag when adding).
- **SC-002**: 100% of existing sessions created before this feature continue to function identically after the upgrade (zero migration effort for current users).
- **SC-003**: Users can manage mixed-agent sessions (different agents in different sessions, including shell-only) from a single Navigator interface, with each session's agent clearly identifiable.
- **SC-004**: Dormant session restore succeeds for all agent configurations, including custom resume commands and shell-only sessions.
- **SC-005**: Users can integrate a previously unknown AI agent by configuring only a start command and a resume command, without modifying Tower's source code.

## Assumptions

- AI CLI agents are invoked as standalone command-line programs (e.g., `claude`, `codex`, `aider`, `gemini`) that can run in a terminal/tmux pane.
- The resume command is a full command string executed when restoring or restarting. Agents that don't support resume can set an empty resume command (equivalent to shell-only for resume).
- The project name "Claude Tower" and repository name remain unchanged as brand identity; only runtime user-facing text (help, errors, Navigator labels) is genericized.
- Per-session agent override is optional; most users will configure a single default agent globally.
- Shell-only sessions (`--program none`) are a first-class feature, not a workaround.

## Scope

### In Scope

- Global agent program and resume command configuration
- Per-session agent program override via `--program` flag on `tower add`
- Shell-only sessions via `--program none`
- Metadata format extension (backward compatible)
- User-facing text genericization (runtime messages, help, Navigator UI)
- Backward compatibility with existing sessions

### Out of Scope

- Agent-specific feature integrations (e.g., Claude's MCP, Codex's sandbox mode)
- Agent auto-detection or discovery
- Renaming the project or repository
- Package manager integration for installing agents
- Tab completion for agent names
- Per-session resume command override (global only; may be added in future)
