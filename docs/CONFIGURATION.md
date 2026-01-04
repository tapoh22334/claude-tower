# Claude Tower Configuration Reference

Complete configuration reference for Claude Tower (v3.2).

## tmux Options

Set these in your `~/.tmux.conf`:

| Option | Default | Description |
|--------|---------|-------------|
| `@tower-prefix` | `t` | Key to open Navigator after tmux prefix |
| `@tower-auto-restore` | `0` | Auto-restore dormant sessions on plugin load |

### Examples

```bash
# Use 's' instead of 't' for Navigator
set -g @tower-prefix 's'

# Automatically restore dormant sessions when tmux starts
set -g @tower-auto-restore '1'
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_TOWER_PROGRAM` | `claude` | Program to run in new sessions |
| `CLAUDE_TOWER_WORKTREE_DIR` | `~/.claude-tower/worktrees` | Directory for git worktrees |
| `CLAUDE_TOWER_METADATA_DIR` | `~/.claude-tower/metadata` | Directory for session metadata |
| `CLAUDE_TOWER_NAV_SOCKET` | `claude-tower` | tmux socket name for Navigator server |
| `CLAUDE_TOWER_NAV_WIDTH` | `40` | Navigator list pane width (percentage) |
| `CLAUDE_TOWER_DEBUG` | `0` | Enable debug logging (1=enabled) |
| `CLAUDE_TOWER_PREFIX` | `t` | Alternative to `@tower-prefix` option |

### Setting Environment Variables

Add to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
# Custom worktree location
export CLAUDE_TOWER_WORKTREE_DIR="$HOME/worktrees"

# Run a different Claude version
export CLAUDE_TOWER_PROGRAM="claude-beta"

# Wider Navigator pane
export CLAUDE_TOWER_NAV_WIDTH="50"

# Enable debug logging
export CLAUDE_TOWER_DEBUG=1
```

## Directory Structure

Claude Tower uses the following directories:

```
~/.claude-tower/
├── worktrees/              # Git worktrees for workspace sessions
│   ├── project-a/
│   └── project-b/
└── metadata/               # Session metadata files
    ├── tower_project-a
    └── tower_project-b

/tmp/claude-tower/          # Runtime state (cleared on reboot)
├── caller                  # Session to return to on quit
├── selected                # Currently selected session
└── focus                   # Current focus (list/view)
```

## Metadata File Format

Each session has a metadata file in `~/.claude-tower/metadata/`:

```ini
session_id=tower_example
session_type=workspace
created_at=2026-01-01T00:00:00+00:00
repository_path=/path/to/repo
source_commit=abc123def456
worktree_path=/home/user/.claude-tower/worktrees/example
session_name=example
branch_name=tower/example
repository_name=my-repo
```

## Session Types

| Type | Description | Git Integration |
|------|-------------|-----------------|
| `workspace` | Uses git worktree for isolation | Yes - creates `tower/<name>` branch |
| `simple` | Regular session in current directory | No |

## Session States (v3.2)

| State | Icon | Description |
|-------|------|-------------|
| `active` | `▶` | tmux session exists |
| `dormant` | `○` | Metadata exists but no tmux session |

## Debug Logging

Enable debug logging:

```bash
export CLAUDE_TOWER_DEBUG=1
```

Logs are written to stderr when running scripts directly.

## Related Documentation

- [SPECIFICATION.md](SPECIFICATION.md) - Behavioral specification
- [QUICKSTART.md](QUICKSTART.md) - Getting started guide
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
