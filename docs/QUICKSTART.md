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

```
┌─────────────────────┬────────────────────────────────────────────┐
│ Sessions [ACTIVE]   │                                            │
│                     │  Live preview of selected session          │
│ ▶ [S] session-1     │                                            │
│                     │  $ claude                                  │
│                     │  > Hello! How can I help?                  │
│                     │                                            │
│ j/k:nav D:del n:new │                                            │
└─────────────────────┴────────────────────────────────────────────┘
     List Pane                      View Pane
```

### 2. Create a Session

Press `n` to create a new session.

```
┌─ New Session ───────────┐
│ Name: my-project
│ Worktree? [y/n]: n
│ Creating...
│ ✓ Created: my-project
└─────────────────────────┘
```

### 3. Work in Your Session

- Press `Enter` to attach to the selected session
- Claude Code starts automatically
- Press `prefix + t` anytime to return to Navigator

### 4. Navigate Between Sessions

| Key | Action |
|-----|--------|
| `j` / `↓` | Move down |
| `k` / `↑` | Move up |
| `Enter` | Attach to session |
| `i` | Focus view pane (input mode) |
| `Escape` | Return to list (from view) |
| `n` | Create new session |
| `D` | Delete session |
| `q` | Quit Navigator |

## Common Workflows

### Switching Between Sessions

1. Press `prefix + t` to open Navigator
2. Use `j`/`k` to select a session
3. Press `Enter` to attach

### Quick Preview and Input

1. Press `prefix + t` to open Navigator
2. Select a session with `j`/`k` (view updates automatically)
3. Press `i` to focus the view pane
4. Type your command to Claude
5. Press `Escape` to return to list

### Restoring Dormant Sessions

Dormant sessions (○) are saved but not running:

- `r` - Restore selected dormant session
- `R` - Restore all dormant sessions
- `Enter` - Attach (auto-restores if dormant)

### Viewing Multiple Sessions

Press `Tab` to switch to tile view:
- See multiple sessions at once
- Press `1-9` to select by number
- Press `Tab` or `Enter` to return to list view
- Press `q` to quit Navigator

## Session Types

### Worktree Mode [W]

Best for git repositories:

```
n → my-feature → y (worktree)
```

Creates:
- Git worktree at `~/.claude-tower/worktrees/my-feature`
- Branch `tower/my-feature`
- Persists as dormant session

### Simple Mode [S]

Best for quick tasks:

```
n → scripts → n (no worktree)
```

Creates:
- Session in home directory
- No git integration
- Lost on tmux restart

## Tips

### Keyboard Efficiency

- `g` - Jump to first session
- `G` - Jump to last session
- `?` - Show full help

### Delete with Confirmation

Press `D` to delete:

```
┌─ Delete Session ────────┐
│ Session: my-project
│ Confirm? [y/n]:
└─────────────────────────┘
```

### Check Status

```bash
make status
```

Shows:
- Navigator server status
- Session server status
- State files

### Reset Everything

```bash
make reset
```

## Next Steps

- [CONFIGURATION.md](CONFIGURATION.md) - Customize settings
- [SPECIFICATION.md](SPECIFICATION.md) - Full feature reference
