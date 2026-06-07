# Claude Tower tmux Plugin

This directory contains the core tmux plugin implementation for Claude Tower.

## Structure

```
tmux-plugin/
├── claude-tower.tmux      # Plugin entry point (loaded by tpm)
├── bin/
│   └── tower              # CLI entry point (tower add/rm/list/restore)
├── conf/
│   └── view-focus.conf    # tmux configuration for view pane focus mode
├── lib/
│   ├── common.sh          # Shared utilities (v2 metadata, session ops)
│   └── error-recovery.sh  # Error handling and TUI recovery
└── scripts/
    ├── navigator.sh        # Navigator entry point
    ├── navigator-list.sh   # List pane UI (n/d/1-9; Tab → Tile via switch_to_tile)
    ├── navigator-view.sh   # View pane UI (input mode)
    ├── return-to-caller.sh # prefix+t handler — return to caller session
    ├── statusline.sh       # tmux status line content
    ├── session-add.sh      # Add session (called by tower add and Navigator n)
    ├── session-delete.sh   # Delete session (called by tower rm and Navigator d)
    ├── session-list.sh     # List sessions
    └── session-restore.sh  # Restore dormant sessions
```

Tile View is native tmux: `switch_to_tile` in `navigator-list.sh` creates a
`tower-tile` window with one `split-window` per active session and applies
the `tiled` layout. Each pane is a nested `tmux attach-session -t tower_X`
configured by `conf/tile-pane.conf`. There is no `tile.sh` any more.

## Key Components

### claude-tower.tmux
Plugin entry point loaded by TPM (Tmux Plugin Manager). Sets up keybindings and initializes the tower environment.

### bin/tower
CLI entry point for session management:
- `tower` (no args) - Launch Navigator
- `tower add <path> [-n name]` - Add session for directory
- `tower rm <name> [-f]` - Remove session (keeps directory)
- `tower list` - List all sessions
- `tower restore` - Restore all dormant sessions

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
- `navigator-list.sh` - Left pane (session list + `switch_to_tile` orchestrator)
- `navigator-view.sh` - Right pane (live session preview)
- Tile View - native tmux split layout, no dedicated script

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
