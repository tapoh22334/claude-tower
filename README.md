# claude-tower

> **🚧 UNDER DEVELOPMENT - NOT FUNCTIONAL 🚧**
>
> This project is in early development. **Most features do not work yet.**
> Do not install for actual use. Breaking changes will occur without notice.

A tmux plugin for managing Claude Code sessions with tree-style navigation and git worktree integration.

## Features

- **Tree View** - Hierarchical view of sessions, windows, and panes
- **Live Preview** - Preview pane content before switching
- **Git Worktree Integration** - Automatic branch isolation per session
- **Quick Actions** - Create, rename, kill sessions from the picker

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

Press `prefix + t` to open the Navigator directly.

### Navigator

Navigator opens in a dedicated tmux session with a sidebar layout:
- **Left pane**: Session list with vim-style navigation
- **Right pane**: Real-time preview of selected session

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `g` | Go to first session |
| `G` | Go to last session |
| `Enter` | Attach to selected session (restores dormant sessions) |
| `i` | Input mode (send command to session) |
| `Tab` | Switch to tile view |
| `n` | Create new session |
| `d` | Delete session |
| `r` | Restore selected dormant session |
| `R` | Restore all dormant sessions |
| `?` | Show help |
| `q` | Exit Navigator

## Tree View

```
📁 ● [W] project-api  ⎇ tower/feature-auth +5,-2
  ├─ 🪟 0: main ●
  │  └─ ▫ 0: claude ●
  └─ 🪟 1: shell
     └─ ▫ 0: zsh
📁 [S] scripts  (no git)
  └─ 🪟 0: main
     └─ ▫ 0: claude
```

| Icon | Meaning |
|------|---------|
| `[W]` | Workspace - git worktree session |
| `[S]` | Simple - regular session |
| `●` | Active |
| `⎇` | Git branch |

## Session Modes

### Workspace Mode `[W]`

For git repositories:
- Creates worktree at `~/.claude-tower/worktrees/<name>`
- Creates branch `tower/<name>`
- Auto-cleanup on session kill

### Simple Mode `[S]`

For non-git directories:
- Runs in current directory
- No git integration

## Configuration

```bash
# ~/.tmux.conf

# Change tower prefix key (default: t)
# Usage: prefix + <tower-prefix> opens Navigator directly
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

# Metadata directory (default: ~/.claude-tower/metadata)
export CLAUDE_TOWER_METADATA_DIR="$HOME/.claude-tower/metadata"

# Navigator socket name (default: claude-tower)
export CLAUDE_TOWER_NAV_SOCKET="claude-tower"

# Navigator width percentage (default: 40)
export CLAUDE_TOWER_NAV_WIDTH="40"

# Enable debug logging
export CLAUDE_TOWER_DEBUG=1
```

See [docs/CONFIGURATION.md](docs/CONFIGURATION.md) for complete configuration reference.

## Troubleshooting

### Plugin not loading

```bash
# Reload config
tmux source ~/.tmux.conf

# Verify keybindings are registered
tmux list-keys | grep tower

# Should show:
# bind-key -T prefix t switch-client -T tower
# bind-key -T tower c display-popup ...
# etc.
```

### prefix + t not responding

1. Make sure you've reloaded tmux after installing:
   ```bash
   tmux source ~/.tmux.conf
   ```

2. Check if keybinding exists:
   ```bash
   tmux list-keys | grep tower
   ```

3. Verify tmux version (requires 3.2+):
   ```bash
   tmux -V
   ```

### Navigator returns error

1. Check if scripts are executable:
   ```bash
   ls -la ~/.tmux/plugins/claude-tower/tmux-plugin/scripts/*.sh
   ```

2. Test navigator directly:
   ```bash
   ~/.tmux/plugins/claude-tower/tmux-plugin/scripts/navigator.sh
   ```

### Orphaned worktrees

Sessions terminated abnormally may leave worktrees behind:

```bash
# List orphans
~/.tmux/plugins/claude-tower/tmux-plugin/scripts/cleanup.sh --list

# Clean up
~/.tmux/plugins/claude-tower/tmux-plugin/scripts/cleanup.sh
```

## License

MIT
