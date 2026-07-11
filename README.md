# Claude Tower

A tmux plugin for managing multiple Claude Code sessions with a Navigator UI.
Tower tracks Claude sessions themselves (via `~/.claude/projects/`), not
directories or worktrees — any Claude session, however it was started, can be
picked up and managed.

## Features

- **Navigator UI** - Two-pane interface for session management
- **Live Preview** - Real-time view of selected session content
- **Session Registry** - Tracks real Claude sessions via their transcripts
- **Session Persistence** - Dormant sessions restore automatically
- **3-Server Architecture** - Isolated session management

## Requirements

- tmux 3.2+
- git
- Claude Code CLI (`claude`)
- fzf (recommended — enables fuzzy picking in the add flow; without it a
  numbered prompt is used)

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
│ ● my-feature        │  displayed here in real-time               │
│ ▶ experiment        │                                            │
│ ○ old-project       │  Use 'i' to focus and interact              │
│ ✗ missing-cwd       │  Use Escape to return to list               │
│                     │                                            │
│ j/k:nav n:add D:del │                                            │
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
| `n` | Add session (existing Claude session or new) |
| `D` | Delete session |
| `r` | Resume dormant session |
| `?` | Show help |
| `q` | Quit Navigator |

### Session States

| Icon | State | Description |
|------|-------|--------------|
| `●` | Busy | Claude is actively working |
| `▶` | Active | tmux session is running (idle) |
| `○` | Dormant | Registered, no tmux session — press `r` to resume |
| `✗` | Dead | Registered, but the session's working directory is gone |
| `?` | Lost | Registered, but the Claude transcript is gone (unrecoverable) |

## Architecture

Claude Tower uses 3 dedicated tmux servers:

| Server | Socket | Purpose |
|--------|--------|---------|
| Navigator | `claude-tower` | Control plane (UI) |
| Session | `claude-tower-sessions` | Data plane (Claude sessions) |
| Default | (user's) | User environment (isolated) |

This isolation prevents Claude Tower from interfering with your regular tmux sessions.

Session state is derived from two sources:
- `~/.claude/projects/<slug>/<sessionId>.jsonl` — the Claude session transcript
  (existence, activity, and cwd).
- `~/.claude-tower/metadata/*.meta` — a minimal Tower registry entry mapping a
  `tower_<uuid>` id to the Claude session it was registered from.

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

# Directory Claude's ~/.claude/projects/ transcripts are read from
# (default: ~/.claude/projects)
export CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"

# Seconds since last transcript activity before a running session is
# considered idle instead of busy (default: 45)
export TOWER_BUSY_WINDOW=45

# Command used to pick a session/directory in the add flow
# (default: "fzf --height=80% --reverse --no-multi"; falls back to a
# numbered prompt if the binary isn't found)
export TOWER_FINDER="fzf --height=80% --reverse --no-multi"

# Default directory offered when adding/creating a session from Navigator
# (set internally to the caller pane's cwd; can be overridden)
export TOWER_ADD_DEFAULT_DIR="$PWD"
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

## Migration from v3.x

Tower now tracks Claude sessions (via `~/.claude/projects/`) instead of
directories/worktrees.

- Existing worktrees keep working: press `n` and pick the session running there.
- Tower no longer deletes worktrees or branches on session delete.
  Clean up manually with `git worktree remove` / `git branch -d`.
- Old registry entries (`~/.claude-tower/metadata/*.meta` with non-UUID names)
  show up as `?` (unrecoverable) — press `D` to clear them.
- Claude auto-deletes transcripts after ~30 days; unregistered sessions older
  than that cannot be re-added.

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
