# Claude Tower tmux Plugin

This directory contains the core tmux plugin implementation for Claude Tower.

## Structure

```
tmux-plugin/
├── claude-tower.tmux      # Plugin entry point (loaded by tpm)
├── conf/
│   └── view-focus.conf    # tmux configuration for view pane focus mode
├── lib/
│   ├── common.sh          # Shared utilities (400+ lines)
│   └── error-recovery.sh  # Error handling and TUI recovery
└── scripts/
    ├── navigator.sh       # Navigator entry point
    ├── navigator-list.sh  # List pane UI (21 KB)
    ├── navigator-view.sh  # View pane UI (12 KB)
    ├── tile.sh            # Tile view display
    ├── session-new.sh     # Create new session
    ├── session-delete.sh  # Delete session
    ├── session-restore.sh # Restore dormant sessions
    ├── session-list.sh    # List sessions
    ├── cleanup.sh         # Orphan worktree cleanup
    ├── tower.sh           # Main CLI entry point
    └── [other utilities]
```

## Key Components

### claude-tower.tmux
Plugin entry point loaded by TPM (Tmux Plugin Manager). Sets up keybindings and initializes the tower environment.

### lib/common.sh
Shared library providing:
- Session state management (`get_session_state`, `list_all_sessions`)
- Metadata operations (`save_metadata`, `load_metadata`)
- Security functions (`sanitize_name`, `validate_path_within`)
- Navigator helpers (`get_nav_focus`, `set_nav_focus`)
- Error handling (`handle_error`, `die`)

### lib/error-recovery.sh
TUI error recovery patterns:
- `show_tui_error()` - Display error in tmux pane
- `error_recovery_wrapper()` - Wrap commands with retry logic
- Safe command execution with timeout

### Navigator Scripts
- `navigator.sh` - Entry point, launched via `prefix + t`
- `navigator-list.sh` - Left pane showing session list
- `navigator-view.sh` - Right pane showing live session preview
- `tile.sh` - Grid view of all sessions

## Session States (v3.2)

| State | Icon | Description |
|-------|------|-------------|
| `active` | `▶` | tmux session exists |
| `dormant` | `○` | Metadata only, no tmux session |

## Architecture

The plugin uses a **socket separation** architecture:
- **default server**: User's regular tmux sessions
- **navigator server** (`-L claude-tower`): Navigator UI runs here

This ensures Navigator operations don't interfere with user sessions.

## For Developers

See `/docs/SPECIFICATION.md` for the authoritative behavioral specification.
See `/docs/PSEUDOCODE.md` for implementation reference.
