# Glossary - Ubiquitous Language

This document defines the domain terminology used throughout the claude-tower codebase.
All contributors should use these terms consistently in code, comments, and documentation.

## Core Concepts

| Term | Definition | Usage Context |
|------|------------|---------------|
| **Session** | A tmux work unit containing multiple windows | All code |
| **Window** | A view within a session containing multiple panes | All code |
| **Pane** | A split region within a window | All code |
| **Session ID** | The tmux session identifier with `tower_` prefix (e.g., `tower_my-project`) | Internal implementation |
| **Session Type** | The kind of session: `workspace` or `simple` | `@tower_session_type` option, metadata |

## Session State (v3.2)

| Term | Definition | Icon | Usage Context |
|------|------------|------|---------------|
| **active** | tmux session exists (`tmux has-session` succeeds) | `▶` | Navigator display, state determination |
| **dormant** | tmux session does not exist, but metadata file exists | `○` | Session restoration, Navigator display |

**Note**: The `exited` state (Claude process finished) was removed in v3.2. If a tmux session exists, it is treated as `active`. Claude's running state should be determined within the session itself, not at the Navigator level.

## Session Types

| Term | Definition | Usage Context |
|------|------------|---------------|
| **Workspace Session** | A session using Git worktree for isolated work | Workspace mode features |
| **Simple Session** | A regular session without Git integration | Simple mode features |

## Git Integration

| Term | Definition | Usage Context |
|------|------------|---------------|
| **Worktree** | A Git feature providing an independent working directory | Workspace sessions |
| **Source Commit** | The commit from which a worktree was created | `@tower_source` option, metadata |
| **Source Branch** | The branch from which a worktree was created | Worktree creation |
| **Repository Path** | The path to the main Git repository | `@tower_repository` option, metadata |

## Orphaned Resources

| Term | Definition | Usage Context |
|------|------------|---------------|
| **Orphaned Worktree** | A worktree without a corresponding active tmux session | Cleanup operations |
| **Active Session** | A tmux session that currently exists | Orphan detection |

## UI State

| Term | Definition | Usage Context |
|------|------------|---------------|
| **Active** | The element currently selected/focused by the user | UI indicators, active_session/window/pane |
| **Selected** | The element chosen by the user in the picker | handle_selection, selected_* variables |

## Data Management

| Term | Definition | Usage Context |
|------|------------|---------------|
| **Metadata** | Session information persisted to files | Metadata management functions |

## Security Functions

| Term | Definition | Usage Context |
|------|------------|---------------|
| **Sanitize** | Remove dangerous characters from user input to prevent injection | `sanitize_name()` |
| **Validate** | Check that a path stays within allowed boundaries | `validate_path_within()` |
| **Normalize** | Convert user input to internal session ID format | `normalize_session_name()` |

## Processing Flow

```
User Input → sanitize_name() → normalize_session_name() → Session ID
    ↓              ↓                    ↓                     ↓
"my project"  "my_project"      "tower_my_project"    Used in tmux
```

## Variable Naming Conventions

### Session-Related
- `session_id`: Full tmux session identifier with `tower_` prefix
- `sanitized_name`: User input after sanitization
- `selected_session`: Session chosen by user in picker
- `active_session`: Currently focused session

### Git-Related
- `repository_path`: Path to main Git repository
- `source_commit`: Commit worktree was created from
- `source_branch`: Branch worktree was created from
- `worktree_path`: Path to the Git worktree directory

### UI-Related
- `active_indicator`: Visual marker for active items
- `session_type`: Display type indicator (W/S)
- `git_branch_display`: Formatted branch name for display
- `diff_stats`: Formatted diff statistics for display

## Operations

| Operation | Function | Description |
|-----------|----------|-------------|
| Cleanup | `remove_orphaned_worktree()` | Remove orphaned worktree and metadata |
| Remove | `git worktree remove` | Git operation to delete worktree |
| Delete | `delete_metadata()` | Remove metadata file only |
| Kill | `tmux kill-session` | Terminate tmux session |

## Metadata File Format

```
session_id=tower_example
session_type=workspace
created_at=2025-01-01T00:00:00+00:00
repository_path=/path/to/repo
source_commit=abc123def456
worktree_path=/home/user/.claude-tower/worktrees/example
```
