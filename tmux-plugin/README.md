# Claude Tower tmux Plugin

This directory contains the core tmux plugin implementation for Claude Tower.

## Structure

```
tmux-plugin/
├── claude-tower.tmux        # Plugin entry point (loaded by tpm)
├── conf/
│   └── view-focus.conf      # tmux configuration for view pane focus mode
├── lib/
│   ├── common.sh            # Shared utilities: session state, metadata, security
│   ├── claude-sessions.sh   # Reads ~/.claude/projects/ jsonl transcripts
│   └── error-recovery.sh    # Error handling and TUI recovery
└── scripts/
    ├── navigator.sh         # Navigator entry point
    ├── navigator-list.sh    # List pane UI
    ├── navigator-view.sh    # View pane UI
    ├── tile.sh              # Tile view display
    ├── session-add.sh       # Unified add/new flow (fzf or numbered picker)
    ├── session-delete.sh    # Delete session (registry only)
    ├── session-restore.sh   # Restore dormant sessions
    ├── session-list.sh      # List sessions
    └── tower.sh             # Main CLI entry point
```

## Key Components

### claude-tower.tmux
Plugin entry point loaded by TPM (Tmux Plugin Manager). Sets up keybindings and initializes the tower environment.

### lib/common.sh
Shared library providing:
- Session state management (`get_session_state`, `get_state_icon`, `list_all_sessions`)
- Metadata operations (`save_metadata`, `load_metadata`, minimal `.meta` registry)
- Security functions (`sanitize_name`, `validate_path_within`, `ensure_tower_prefix`)
- Navigator helpers (`get_nav_focus`, `set_nav_focus`, `get_nav_selected`)
- Error handling (`handle_error`, `die`)

### lib/claude-sessions.sh
Derives session state from Claude's own transcripts under
`~/.claude/projects/<slug>/<sessionId>.jsonl`: busy/idle detection
(`is_session_busy`, `TOWER_BUSY_WINDOW`), the full 5-state Navigator check
(`get_display_state`: busy/active/dormant/dead/lost), and candidate discovery
for the add flow (`list_addable_sessions`).

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

## Session States

| State | Icon | Description |
|-------|------|-------------|
| `busy` | `●` | tmux session exists, Claude active within `TOWER_BUSY_WINDOW` |
| `active` | `▶` | tmux session exists, idle |
| `dormant` | `○` | Registered, no tmux session — can be resumed |
| `dead` | `✗` | Registered, but the session's working directory is gone |
| `lost` | `?` | Registered, but the Claude transcript is gone (unrecoverable) |

## Architecture

The plugin uses a **socket separation** architecture:
- **default server**: User's regular tmux sessions
- **navigator server** (`-L claude-tower`): Navigator UI runs here

This ensures Navigator operations don't interfere with user sessions.

## For Developers

See `/docs/SPECIFICATION.md` for the authoritative behavioral specification.
See `/docs/PSEUDOCODE.md` for implementation reference.
