# claude-tower

> **⚠️ UNDER DEVELOPMENT**
> This project is currently under active development and not ready for production use.
> Features may be incomplete, and breaking changes may occur without notice.

A tmux plugin for managing Claude Code sessions with tree-style navigation and git worktree integration.

## Features

- **Tree View** - Hierarchical view of sessions, windows, and panes
- **Live Preview** - Preview pane content before switching
- **Git Worktree Integration** - Automatic branch isolation per session
- **Quick Actions** - Create, rename, kill sessions from the picker

## Requirements

- tmux 3.2+ (for display-popup support)
- git
- Claude Code CLI (`claude`)
- [gum](https://github.com/charmbracelet/gum) (for Navigator UI)

```bash
# Install gum
brew install gum
```

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

Press `prefix + t` to enter Tower mode, then use one of the following keys:

| Key | Action |
|-----|--------|
| `prefix + t c` | Open Navigator (session picker) |
| `prefix + t t` | Create new session |
| `prefix + t n` | Create new session (alias) |
| `prefix + t l` | List sessions |
| `prefix + t r` | Restore sessions |
| `prefix + t ?` | Show help |

### Navigator Keybindings (Vim-style)

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `g` | Go to first session |
| `G` | Go to last session |
| `5G` | Jump to session 5 (number+G) |
| `/pattern` | Search sessions |
| `N` | Next search result |
| `Enter` | Attach to selected session |
| `i` | Input mode (send command) |
| `T` | Tile mode (view all sessions) |
| `c` | Create new session |
| `d` | Delete session |
| `R` | Restart Claude |
| `?` | Show help |
| `q` / `Esc` | Exit Navigator |

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
# Usage: prefix + <tower-prefix>, then c/t/n/l/r/?
set -g @tower-prefix 't'
```

### Environment Variables

```bash
# Program to run (default: claude)
export CLAUDE_TOWER_PROGRAM="claude"

# Worktree directory (default: ~/.claude-tower/worktrees)
export CLAUDE_TOWER_WORKTREE_DIR="$HOME/.claude-tower/worktrees"

# Enable debug logging
export CLAUDE_TOWER_DEBUG=1
```

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

2. Check if tower key table exists:
   ```bash
   tmux list-keys -T tower
   ```

3. Verify tmux version (requires 3.2+ for display-popup):
   ```bash
   tmux -V
   ```

### Navigator (prefix + t, c) returns error

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
