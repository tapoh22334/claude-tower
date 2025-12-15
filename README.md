# claude-tower

A tmux plugin for managing Claude Code sessions with tree-style navigation and git worktree integration.

## Features

- **Tree View** - Hierarchical view of sessions, windows, and panes
- **Live Preview** - Preview pane content before switching
- **Git Worktree Integration** - Automatic branch isolation per session
- **Quick Actions** - Create, rename, kill sessions from the picker

## Requirements

- tmux 3.0+
- fzf
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

| Key | Action |
|-----|--------|
| `prefix + C` | Open session picker |
| `prefix + T` | Create new session |

### Picker Keybindings

| Key | Action |
|-----|--------|
| `Enter` | Switch to selection |
| `n` | New session |
| `r` | Rename session |
| `x` | Kill session |
| `D` | Show git diff |
| `?` | Help |

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

# Change keybindings
set -g @tower-key 'C'
set -g @tower-new-key 'T'
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

# Verify keybindings
tmux list-keys | grep tower
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
