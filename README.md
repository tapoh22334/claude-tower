# Claude Tower

A tmux plugin for managing multiple Claude Code sessions with Navigator UI and git worktree integration.

## Features

- **Navigator UI** - Two-pane interface for session management
- **Live Preview** - Real-time view of selected session content
- **Git Worktree Integration** - Automatic branch isolation per session
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

Press `prefix + t` to open the Navigator.

### Navigator UI

```
┌─────────────────────┬────────────────────────────────────────────┐
│ Sessions [ACTIVE]   │                                            │
│                     │  Claude Code session content               │
│ ▶ [W] my-feature    │  displayed here in real-time               │
│   [S] experiment    │                                            │
│ ○ [W] old-project   │  Use 'i' to focus and interact             │
│                     │  Use Escape to return to list              │
│                     │                                            │
│ j/k:nav D:del n:new │                                            │
└─────────────────────┴────────────────────────────────────────────┘
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
| `n` | Create new session |
| `D` | Delete session |
| `r` | Restore selected dormant session |
| `R` | Restore all dormant sessions |
| `?` | Show help |
| `q` | Quit Navigator |

### Session States

| Icon | State | Description |
|------|-------|-------------|
| `▶` | Active | Claude is running |
| `○` | Dormant | Session saved, can be restored |

### Session Types

| Icon | Type | Description |
|------|------|-------------|
| `[W]` | Worktree | Git worktree managed session |
| `[S]` | Simple | Regular session (no git) |

## Session Types

### Worktree Session `[W]`

For git repositories:
- Creates worktree at `~/.claude-tower/worktrees/<name>`
- Creates branch `tower/<name>`
- Persists as dormant when closed
- Auto-cleanup on delete

### Simple Session `[S]`

For quick tasks:
- Runs in specified directory
- No git integration
- Volatile (lost on tmux restart)

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

# Worktree directory (default: ~/.claude-tower/worktrees)
export CLAUDE_TOWER_WORKTREE_DIR="$HOME/.claude-tower/worktrees"

# Metadata directory (default: ~/.claude-tower/sessions)
export CLAUDE_TOWER_METADATA_DIR="$HOME/.claude-tower/sessions"

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
