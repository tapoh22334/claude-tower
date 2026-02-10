# Claude Tower

A tmux plugin for managing multiple Claude Code sessions with Navigator UI.

## Features

- **Navigator UI** - Two-pane interface for session management
- **Live Preview** - Real-time view of selected session content
- **Session Persistence** - Dormant sessions restore automatically
- **Directory-Based Sessions** - Work with any directory
- **3-Server Architecture** - Isolated session management

## Requirements

- tmux 3.2+
- git (optional, for repository management)
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

## Quick Start

```bash
# Launch Navigator UI
prefix + t

# Or use CLI
tower add ~/projects/myapp              # Add a directory as session
tower add . -n custom-name              # Add current dir with custom name
tower rm my-session                     # Remove a session
tower list                              # List all sessions
```

## Usage

### Navigator UI

Press `prefix + t` to open the Navigator.

```
┌─────────────────────┬────────────────────────────────────────────┐
│ Sessions [ACTIVE]   │                                            │
│                     │  Claude Code session content               │
│ ▶ myapp             │  displayed here in real-time               │
│   /home/user/proj.. │                                            │
│ ○ experiment        │  Use 'i' to focus and interact             │
│   /home/user/test   │  Use Escape to return to list              │
│                     │                                            │
│ j/k:nav r:restore   │                                            │
└─────────────────────┴────────────────────────────────────────────┘
     List Pane (24%)              View Pane (76%)
```

### Navigator Keybindings

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

### CLI Commands

```bash
tower add <path> [-n name]       # Add directory as session
tower rm <name> [-f]             # Remove session
tower list                       # List all sessions
tower restore [--all]            # Restore dormant sessions
tower tile                       # Launch tile view
tower help                       # Show help
```

### Session States

| Icon | State | Description |
|------|-------|-------------|
| `▶` | Active | Session is running |
| `○` | Dormant | Session saved, can be restored |

## How It Works

Tower manages Claude Code sessions by:
- Creating tmux sessions for each directory you add
- Storing session metadata (name, directory path, creation time)
- Allowing you to restore sessions even after tmux restart
- **You manage directories** - Tower only manages sessions

Tower does NOT:
- Create or delete directories
- Manage git repositories or branches
- Interfere with your files or worktrees

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

## Migration Guide (v1 → v2)

### What Changed

**v2.0 is a breaking change** that simplifies Tower to focus on session management only.

#### Removed Features
- ❌ Git worktree automatic creation and management
- ❌ Session types (`[W]` Worktree / `[S]` Simple)
- ❌ Navigator inline creation (`n` key) and deletion (`D` key)
- ❌ Automatic directory cleanup on session delete

#### New Features
- ✅ `tower add` - Add any directory as a session
- ✅ `tower rm` - Remove sessions (directories remain untouched)
- ✅ Path display in Navigator instead of type icons
- ✅ Simplified metadata (only essential fields)

### Migration Steps

#### 1. Existing Sessions

Your existing sessions will continue to work:
- Metadata is readable (backward compatible)
- Sessions can be restored normally
- **Important**: Deleting a session will no longer remove git worktrees

#### 2. Clean Up Old Worktrees (Optional)

If you have old `[W]` sessions with worktrees:

```bash
# List all worktrees
git worktree list

# Remove specific worktree
git worktree remove ~/.claude-tower/worktrees/<name>

# Or force remove if needed
git worktree remove --force ~/.claude-tower/worktrees/<name>

# Clean up orphaned worktrees
git worktree prune
```

#### 3. Update Your Workflow

**Old workflow:**
```bash
# v1 - creates git worktree
tower new -n my-feature -w

# v1 - deletes worktree and branch
tower delete my-feature
```

**New workflow:**
```bash
# v2 - just add existing directory
tower add ~/projects/myapp -n my-feature

# v2 - only removes session (directory untouched)
tower rm my-feature
```

#### 4. Navigator Changes

**Old keys (removed):**
- `n` - Create new session → **Use CLI: `tower add <path>`**
- `D` - Delete session → **Use CLI: `tower rm <name>`**

**Keys still available:**
- `r` / `R` - Restore dormant sessions
- `Enter` - Attach to session
- `i` - Input mode

### Philosophy Change

**v1:** Tower manages both sessions and directories (git worktrees)
**v2:** Tower manages sessions, **you manage directories**

This makes Tower simpler, more flexible, and works with any directory structure.

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

### Clean up orphaned metadata

```bash
# List orphaned metadata (sessions without active tmux sessions)
tmux-plugin/scripts/cleanup.sh --list

# Remove orphaned metadata interactively
tmux-plugin/scripts/cleanup.sh

# Force remove all orphaned metadata
tmux-plugin/scripts/cleanup.sh --force
```

## License

MIT
