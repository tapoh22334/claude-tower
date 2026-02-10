# Claude Tower tmux Plugin

This directory contains the core tmux plugin implementation for Claude Tower.

## Structure

```
tmux-plugin/
├── claude-tower.tmux      # Plugin entry point (loaded by tpm)
├── conf/
│   └── view-focus.conf    # tmux configuration for view pane focus mode
├── lib/
│   ├── common.sh          # Shared utilities (v2 metadata, session ops)
│   └── error-recovery.sh  # Error handling and TUI recovery
└── scripts/
    ├── tower              # CLI entry point (tower add/rm)
    ├── session-add.sh     # tower add implementation
    ├── session-delete.sh  # tower rm implementation
    ├── navigator.sh       # Navigator entry point
    ├── navigator-list.sh  # List pane UI
    ├── navigator-view.sh  # View pane UI
    ├── tile.sh            # Tile view display
    ├── session-new.sh     # [DEPRECATED] Use tower add
    ├── session-restore.sh # Restore dormant sessions
    ├── session-list.sh    # List sessions
    ├── cleanup.sh         # Dormant session cleanup
    └── [other utilities]
```

## Key Components

### claude-tower.tmux
Plugin entry point loaded by TPM (Tmux Plugin Manager). Sets up keybindings and initializes the tower environment.

### scripts/tower
CLI entry point for session management:
- `tower add <path> [-n name]` - Add session for directory
- `tower rm <name> [-f]` - Remove session (keeps directory)

### lib/common.sh
Shared library providing:
- Session state management (`get_session_state`, `list_all_sessions`)
- Metadata operations (`save_metadata`, `load_metadata`) - v2 format
- Session operations (`create_session`, `delete_session`, `restore_session`)
- Security functions (`sanitize_name`, `validate_path_within`)
- Navigator helpers (`get_nav_focus`, `set_nav_focus`)
- Error handling (`handle_error`, `die`)
- Path helpers (`shorten_path` - replaces $HOME with ~)

### lib/error-recovery.sh
TUI error recovery patterns:
- `show_tui_error()` - Display error in tmux pane
- `error_recovery_wrapper()` - Wrap commands with retry logic
- Safe command execution with timeout

### Navigator Scripts
- `navigator.sh` - Entry point, launched via `prefix + t`
- `navigator-list.sh` - Left pane showing session list with paths
- `navigator-view.sh` - Right pane showing live session preview
- `tile.sh` - Grid view of all sessions

## Session States

| State | Icon | Description |
|-------|------|-------------|
| `active` | `▶` | tmux session exists |
| `dormant` | `○` | Metadata only, no tmux session |

## Metadata Format (v2)

```ini
session_id=tower_my-project
session_name=my-project
directory_path=/home/user/projects/my-project
created_at=2026-02-08T10:30:00+09:00
```

v1 metadata (with `worktree_path`, `repository_path`) is still readable for backward compatibility.

## Architecture

The plugin uses a **socket separation** architecture:
- **default server**: User's regular tmux sessions
- **navigator server** (`-L claude-tower`): Navigator UI runs here
- **session server** (`-L claude-tower-sessions`): Claude Code sessions run here

This ensures Navigator operations don't interfere with user sessions.

## For Developers

See `/docs/SPECIFICATION.md` for the authoritative behavioral specification.
See `/docs/PSEUDOCODE.md` for implementation reference.
