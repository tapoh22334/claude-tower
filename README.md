# Claude Tower

> **⚠️ Under Development** - このプロジェクトは開発中です。APIや機能は予告なく変更される可能性があります。

A tmux plugin for managing multiple Claude Code sessions with Navigator UI.

## Features

- **Navigator UI** - Two-pane interface for session management
- **Live Preview** - Real-time view of selected session content
- **CLI Commands** - `tower add` / `tower rm` for session management
- **Session Persistence** - Dormant sessions restore automatically
- **3-Server Architecture** - Isolated session management

## Requirements

- tmux 3.2+
- git
- Claude Code CLI (`claude`)

## Installation

### TPM (recommended)

```bash
set -g @plugin 'tapoh22334/claude-tower'
```

Press `prefix + I` to install.

### Manual

```bash
git clone https://github.com/tapoh22334/claude-tower ~/.tmux/plugins/claude-tower
```

Add to `~/.tmux.conf`:

```bash
run-shell ~/.tmux/plugins/claude-tower/tmux-plugin/claude-tower.tmux
```

## Usage

### CLI Commands

```bash
# Add a new session for a directory
tower add /path/to/project
tower add . -n my-session    # with custom name

# Remove a session (directory is NOT deleted)
tower rm my-session
tower rm my-session -f       # force (no confirmation)
```

### Navigator UI

Press `prefix + t` to open the Navigator.

```
┌───────────────────────────┬────────────────────────────────────────┐
│ Sessions [ACTIVE]         │                                        │
│                           │  Claude Code session content           │
│ ▶ my-feature  ~/proj/app  │  displayed here in real-time           │
│   experiment  ~/tmp/test  │                                        │
│ ○ old-project ~/work/old  │  Use 'i' to focus and interact         │
│                           │  Use Escape to return to list          │
│                           │                                        │
│ j/k:nav Enter:attach q:quit                                        │
└───────────────────────────┴────────────────────────────────────────┘
     List Pane (24%)              View Pane (76%)
```

### Keybindings

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `g` | Go to first session |
| `G` | Go to last session |
| `Enter` | Attach to selected session |
| `i` | Focus view pane (input mode) |
| `Escape` | Return to list (from view) |
| `Tab` | Switch to tile view |
| `r` | Restore selected dormant session |
| `R` | Restore all dormant sessions |
| `?` | Show help |
| `q` | Quit Navigator |

### Session States

| Icon | State | Description |
|------|-------|-------------|
| `▶` | Active | Claude is running |
| `○` | Dormant | Session saved, can be restored |

## How It Works

1. **Add a session** with `tower add <path>` - creates a session pointing to your directory
2. **Use Navigator** (`prefix + t`) to switch between sessions
3. **Remove a session** with `tower rm <name>` - the directory is never deleted

Sessions are just references to directories. Tower does not create, modify, or delete your project directories.

## Architecture

Claude Tower uses 3 dedicated tmux servers:

| Server | Socket | Purpose |
|--------|--------|---------|
| Navigator | `claude-tower` | Control plane (UI) |
| Session | `claude-tower-sessions` | Data plane (Claude sessions) |
| Default | (user's) | User environment (isolated) |

This isolation prevents Claude Tower from interfering with your regular tmux sessions.

## Configuration

```bash
# ~/.tmux.conf

# Change tower prefix key (default: t)
set -g @tower-prefix 't'

# Auto-restore dormant sessions on plugin load (default: 0)
set -g @tower-auto-restore '1'
```

### Environment Variables

```bash
# Program to run (default: claude)
export CLAUDE_TOWER_PROGRAM="claude"

# Metadata directory (default: ~/.claude-tower/metadata)
export CLAUDE_TOWER_METADATA_DIR="$HOME/.claude-tower/metadata"

# Navigator socket name (default: claude-tower)
export CLAUDE_TOWER_NAV_SOCKET="claude-tower"

# Session server socket name (default: claude-tower-sessions)
export CLAUDE_TOWER_SESSION_SOCKET="claude-tower-sessions"

# Navigator list pane width (default: 24)
export CLAUDE_TOWER_NAV_WIDTH="24"

# Enable debug logging
export CLAUDE_TOWER_DEBUG=1
```

## Development

```bash
# Reload plugin after changes
make reload

# Show status of servers and state files
make status

# Reset (kill servers, clear state)
make reset

# Run tests
make test

# Lint scripts
make lint
```

## Migration from v1

If you're upgrading from v1 (with worktree support):

### What Changed

| v1 | v2 |
|----|-----|
| `n` key creates session in Navigator | Use `tower add <path>` CLI |
| `D` key deletes session in Navigator | Use `tower rm <name>` CLI |
| `[W]`/`[S]` type icons | Path display (e.g., `~/projects/app`) |
| Worktree management | Directories are references only |
| Session deletion removes worktree | Session deletion keeps directory |

### Backward Compatibility

- **v1 metadata is still readable** - existing sessions will work
- **Worktree directories are preserved** - Tower no longer deletes them
- **Navigator functions the same** - just use CLI for create/delete

### Recommended Actions

1. Your existing worktree directories at `~/.claude-tower/worktrees/` are safe
2. If you want to clean them up, delete manually: `rm -rf ~/.claude-tower/worktrees/<name>`
3. Re-add sessions with `tower add <path>` pointing to your actual project directories

## Troubleshooting

### Plugin not loading

```bash
# Reload tmux config
tmux source ~/.tmux.conf

# Verify keybinding
tmux list-keys | grep tower
```

### prefix + t not responding

1. Reload tmux config:
   ```bash
   tmux source ~/.tmux.conf
   ```

2. Check tmux version (requires 3.2+):
   ```bash
   tmux -V
   ```

### Check server status

```bash
make status
```

### Reset everything

```bash
make reset
```

## License

MIT
