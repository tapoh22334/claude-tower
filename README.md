# claude-pilot

A tmux plugin for managing Claude Code sessions with tree-style navigation.

## Features

- **Tree View**: See all sessions, windows, and panes in a hierarchical tree
- **Live Preview**: Preview pane content before switching
- **Two Session Modes**:
  - **Workspace** [W]: Git-managed with worktree isolation
  - **Simple** [S]: Regular sessions for non-git directories
- **Quick Actions**: New, rename, kill, diff from the picker

## Requirements

- tmux 3.0+
- fzf
- git (for workspace mode)
- Claude CLI (`claude`)

## Installation

### With TPM (recommended)

Add to your `~/.tmux.conf`:

```bash
set -g @plugin 'your-username/claude-pilot'
```

Then press `prefix + I` to install.

### Manual

```bash
git clone https://github.com/your-username/claude-pilot ~/.tmux/plugins/claude-pilot
```

Add to `~/.tmux.conf`:

```bash
run-shell ~/.tmux/plugins/claude-pilot/tmux-plugin/tmux-pilot.tmux
```

Reload config:

```bash
tmux source ~/.tmux.conf
```

## Usage

| Key | Action |
|-----|--------|
| `prefix + p` | Open session picker |
| `prefix + P` | Create new session |

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

When you create a session in a git repository:
- Creates a new git worktree at `~/.tmux-pilot/worktrees/<name>`
- Creates a branch `claude-pilot/<name>`
- Shows diff stats in the tree view
- Cleans up worktree when session is killed

### Simple Mode [S]

When you create a session outside a git repository:
- Just starts the program in the current directory
- No git integration

## Configuration

Add to `~/.tmux.conf`:

```bash
# Change picker key (default: p)
set -g @pilot-key 'p'

# Change new session key (default: P)
set -g @pilot-new-key 'P'
```

### Environment Variables

```bash
# Program to run in new sessions (default: claude)
export TMUX_PILOT_PROGRAM="claude"

# Worktree storage directory (default: ~/.tmux-pilot/worktrees)
export TMUX_PILOT_WORKTREE_DIR="$HOME/.tmux-pilot/worktrees"
```

### Data Storage

- Sessions metadata: `~/.tmux-pilot/sessions/`
- Worktrees: `~/.tmux-pilot/worktrees/`

## License

MIT
