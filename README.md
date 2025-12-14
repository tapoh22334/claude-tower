# claude-pilot

A tmux plugin for managing Claude Code sessions with tree-style navigation and git worktree integration.

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Tree View](#tree-view)
- [Session Modes](#session-modes)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Features

- **Tree View**: See all sessions, windows, and panes in a hierarchical tree
- **Live Preview**: Preview pane content before switching
- **Two Session Modes**: [Workspace](#workspace-mode-w) for git repos with worktree isolation, [Simple](#simple-mode-s) for regular directories
- **Actions**: New, rename, kill, diff from the picker

## Requirements

- **tmux 3.0+** - [Installation guide](https://github.com/tmux/tmux/wiki/Installing)
- **fzf** - [Installation guide](https://github.com/junegunn/fzf#installation)
- **git** (for workspace mode) - [Installation guide](https://git-scm.com/downloads)
- **Claude Code CLI** (`claude`) - [Download](https://claude.ai/code)

## Installation

### With TPM

Add to your `~/.tmux.conf`:

```bash
set -g @plugin 'claude-pilot/claude-pilot'
```

Then press `prefix + I` to install.

### Manual

```bash
git clone https://github.com/claude-pilot/claude-pilot ~/.tmux/plugins/claude-pilot
```

Add to `~/.tmux.conf`:

```bash
run-shell ~/.tmux/plugins/claude-pilot/tmux-plugin/tmux-pilot.tmux
```

Reload config:

```bash
tmux source ~/.tmux.conf
```

### Verify Installation

Check if the plugin is loaded:

```bash
tmux list-keys | grep pilot
```

You should see key bindings for the pilot plugin.

## Usage

| Key | Action |
|-----|--------|
| `prefix + C` | Open session picker |
| `prefix + T` | Create new session |

> **Note**: The default tmux prefix key is `Ctrl+b`. If you've customized it, use your prefix instead.

### In the Picker

| Key | Action |
|-----|--------|
| `Enter` | Select and switch |
| `n` | New session |
| `r` | Rename session |
| `x` | Kill session |
| `D` | Show git diff (workspace only) |
| `?` | Show help |
| `Esc` | Close |

## Tree View

```
📁 ● [W] project-api  ⎇ pilot/feature-auth +5,-2
  ├─ 🪟 0: main ●
  │  └─ ▫ 0: claude ●
  └─ 🪟 1: shell
     └─ ▫ 0: zsh
📁 [S] scripts  (no git)
  └─ 🪟 0: main
     └─ ▫ 0: claude
```

### Icons

| Icon | Meaning |
|------|---------|
| 📁 | Session |
| 🪟 | Window |
| ▫ | Pane |
| ● | Active |
| ⎇ | Git branch |
| [W] | Workspace mode |
| [S] | Simple mode |

## Session Modes

### Workspace Mode [W]

For git repositories, automatically:

- Creates git worktree at `~/.tmux-pilot/worktrees/<name>`
- Creates branch `pilot/<name>`
- Displays diff stats in tree view
- Removes worktree on session termination

### Simple Mode [S]

For non-git directories:

- Starts program in current directory without git integration

## Configuration

Add to `~/.tmux.conf`:

```bash
# Change picker key (default: C)
set -g @pilot-key 'C'

# Change new session key (default: T)
set -g @pilot-new-key 'T'
```

### Environment Variables

Add to your shell config (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
# Program to run in new sessions (default: claude)
export TMUX_PILOT_PROGRAM="claude"

# Worktree storage directory (default: ~/.tmux-pilot/worktrees)
export TMUX_PILOT_WORKTREE_DIR="$HOME/.tmux-pilot/worktrees"
```

### Data Storage

- **Metadata**: `~/.tmux-pilot/metadata/` - Session info persisted to files
- **Worktrees**: `~/.tmux-pilot/worktrees/` - Git worktrees for workspace sessions

### Cleanup Orphaned Worktrees

If sessions are terminated abnormally (crash, kill -9, etc.), worktrees may be left behind. Use the cleanup tool:

```bash
# List orphaned worktrees
~/.tmux/plugins/claude-pilot/tmux-plugin/scripts/cleanup.sh --list

# Interactive cleanup
~/.tmux/plugins/claude-pilot/tmux-plugin/scripts/cleanup.sh

# Force cleanup (no confirmation)
~/.tmux/plugins/claude-pilot/tmux-plugin/scripts/cleanup.sh --force
```

## Troubleshooting

### Plugin not loading

**Symptoms**: Key bindings don't work after installation

**Solutions**:
1. Reload tmux config: `tmux source ~/.tmux.conf`
2. Restart tmux completely: exit all sessions and start tmux again
3. Check key bindings: `tmux list-keys | grep pilot`

### fzf not found

**Error**: `fzf is required but not installed`

**Solution**: Install fzf and ensure it's in your PATH:

```bash
# macOS
brew install fzf

# Ubuntu/Debian
sudo apt install fzf

# Check installation
which fzf
```

### Worktree already exists

**Error**: `fatal: 'pilot/session-name' already exists`

**Solution**: Remove stale worktree manually:

```bash
git worktree remove ~/.tmux-pilot/worktrees/session-name
git branch -D pilot/session-name
```

### Claude CLI not starting

**Symptoms**: Session created but Claude doesn't start

**Solutions**:
1. Verify Claude CLI is installed: `which claude`
2. Test Claude manually: `claude`
3. Check environment variable: `echo $TMUX_PILOT_PROGRAM`

## License

MIT License - see the [LICENSE](LICENSE) file for details.
