# Claude Tower Quick Start Guide

Get started with Claude Tower in 5 minutes.

## Prerequisites

- tmux 3.2 or later
- git (for workspace mode)
- Claude Code CLI (`claude`)

## Installation

### Using TPM (recommended)

Add to your `~/.tmux.conf`:

```bash
set -g @plugin 'tapoh22334/claude-tower'
```

Then press `prefix + I` to install.

### Manual Installation

```bash
git clone https://github.com/tapoh22334/claude-tower ~/.tmux/plugins/claude-tower
```

Add to `~/.tmux.conf`:

```bash
run-shell ~/.tmux/plugins/claude-tower/tmux-plugin/claude-tower.tmux
```

Reload tmux:

```bash
tmux source ~/.tmux.conf
```

## Your First Session

### 1. Open Navigator

Press `prefix + t` (default: `Ctrl-b t`).

The Navigator opens with two panes:
- **Left**: Session list
- **Right**: Live preview of selected session

### 2. Create a Session

Press `n` to create a new session.

You'll be prompted for:
1. **Session name**: Enter a name (e.g., `my-project`)
2. **Session type**: Choose workspace (git worktree) or simple

### 3. Work in Your Session

After creating a session:
- Claude Code starts automatically
- You're attached to the session
- Press `prefix + t` anytime to return to Navigator

### 4. Navigate Between Sessions

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `Enter` | Attach to session |
| `i` | Send input to preview |
| `q` | Exit Navigator |

## Common Workflows

### Switching Between Sessions

1. Press `prefix + t` to open Navigator
2. Use `j`/`k` to select a session
3. Press `Enter` to attach

### Quick Input to a Session

1. Press `prefix + t` to open Navigator
2. Select a session with `j`/`k`
3. Press `i` to focus the preview pane
4. Type your command
5. Press `prefix + Left/Right` to return to list pane, then `j`/`k`

### Restoring Dormant Sessions

Dormant sessions (○) are saved but not running:

- `r` - Restore selected dormant session
- `R` - Restore all dormant sessions
- `Enter` - Attach (auto-restores if dormant)

### Viewing Multiple Sessions

Press `Tab` to switch to tile view:
- See all sessions at once
- Press `1-9` or `Enter` to select
- Press `Tab` again to return to list view

## Session Types

### Workspace Mode [W]

Best for git repositories:

```
n → my-feature → workspace
```

Creates:
- Git worktree at `~/.claude-tower/worktrees/my-feature`
- Branch `tower/my-feature`
- Isolated working directory

### Simple Mode [S]

Best for quick tasks:

```
n → scripts → simple
```

Creates:
- Session in current directory
- No git integration

## Tips

### Keyboard Efficiency

- `g` jumps to first session
- `G` jumps to last session
- `1-9` selects by number (in tile view)

### Return to Previous Work

Press `q` in Navigator to return to your previous session.

### Clean Up Orphaned Worktrees

If sessions were terminated abnormally:

```bash
~/.tmux/plugins/claude-tower/tmux-plugin/scripts/cleanup.sh
```

## Next Steps

- [CONFIGURATION.md](CONFIGURATION.md) - Customize settings
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Solve common issues
- [SPECIFICATION.md](SPECIFICATION.md) - Full feature reference
