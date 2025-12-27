# Navigator Architecture - Socket Separation Design

## Overview

Navigator uses a dedicated tmux server (`-L claude-tower`) separate from the user's default tmux environment. This allows Navigator to act as a "control center" while keeping Claude Code sessions in the user's familiar environment.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ default tmux server (user's world)                              │
│                                                                 │
│ ├── tower_api        ← Claude Code session                     │
│ ├── tower_frontend   ← Claude Code session                     │
│ ├── tower_scripts    ← Claude Code session                     │
│ ├── my_work          ← User's other work                       │
│ └── ...                                                         │
└─────────────────────────────────────────────────────────────────┘
        ▲
        │ Right pane connects via: TMUX= tmux attach -t <session>
        │
┌───────┴─────────────────────────────────────────────────────────┐
│ -L claude-tower server (Navigator's world)                      │
│                                                                 │
│ └── navigator session                                           │
│     ┌─────────────────┬─────────────────────────────────────┐  │
│     │ Left Pane       │ Right Pane                          │  │
│     │                 │                                     │  │
│     │ Session List    │ Real-time view of                   │  │
│     │ ─────────────   │ selected session                    │  │
│     │ ▶ tower_api     │                                     │  │
│     │   tower_frontend│ (Connected to default server)       │  │
│     │   tower_scripts │                                     │  │
│     │                 │                                     │  │
│     │ ─────────────   │                                     │  │
│     │ j/k: navigate   │ Input directly to session           │  │
│     │ i: focus right  │ Esc: back to list                   │  │
│     │ a: full attach  │                                     │  │
│     │ q: quit         │                                     │  │
│     └─────────────────┴─────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Key Concepts

### Socket Separation

| Server | Socket | Purpose |
|--------|--------|---------|
| default | `/tmp/tmux-{UID}/default` | User's sessions, Claude Code |
| claude-tower | `/tmp/tmux-{UID}/claude-tower` | Navigator only |

### Components

1. **navigator.sh**: Entry point, manages Navigator lifecycle
2. **navigator-list.sh**: Left pane, session list with vim-style navigation
3. **navigator-preview.sh**: Right pane wrapper, manages connection to default server
4. **inner-tmux.conf**: Configuration for the nested tmux client

## User Flow

### Opening Navigator

```
User presses: prefix + t c
         │
         ▼
┌─────────────────────────────────┐
│ 1. Check if Navigator exists    │
│    tmux -L claude-tower         │
│    has-session -t navigator     │
└─────────────────────────────────┘
         │
         ▼ (if not exists)
┌─────────────────────────────────┐
│ 2. Create Navigator session     │
│    tmux -L claude-tower         │
│    new-session -d -s navigator  │
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│ 3. Setup panes                  │
│    - Left: navigator-list.sh    │
│    - Right: navigator-preview.sh│
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│ 4. Switch to Navigator          │
│    TMUX= tmux -L claude-tower   │
│    attach -t navigator          │
└─────────────────────────────────┘
```

### Session Switching (j/k keys)

```
User presses: j (move down)
         │
         ▼
┌─────────────────────────────────┐
│ 1. Update selection index       │
│ 2. Write to selection file      │
│    /tmp/claude-tower/selected   │
│ 3. Send Escape to right pane    │
│    tmux -L claude-tower         │
│    send-keys -t navigator:0.1   │
│    Escape                       │
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│ 4. Right pane's inner tmux      │
│    detaches (Esc binding)       │
│ 5. Wrapper script loops back    │
│ 6. Reads new selection          │
│ 7. Attaches to new session      │
└─────────────────────────────────┘
```

### Input Mode (i key)

```
User presses: i (input mode)
         │
         ▼
┌─────────────────────────────────┐
│ 1. Focus moves to right pane    │
│    tmux -L claude-tower         │
│    select-pane -R               │
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│ 2. User types in right pane     │
│    Input goes directly to       │
│    Claude Code session          │
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│ 3. User presses Esc             │
│    - Inner tmux detaches        │
│    - Wrapper re-attaches        │
│    - Focus returns to left pane │
└─────────────────────────────────┘
```

### Full Attach (a key)

```
User presses: a (full attach)
         │
         ▼
┌─────────────────────────────────┐
│ 1. Kill Navigator session       │
│    tmux -L claude-tower         │
│    kill-session -t navigator    │
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│ 2. Attach to selected session   │
│    in default server            │
│    tmux attach -t tower_api     │
└─────────────────────────────────┘
```

### Quit Navigator (q key)

```
User presses: q (quit)
         │
         ▼
┌─────────────────────────────────┐
│ 1. Kill Navigator session       │
│ 2. Return to previous session   │
│    (stored in state file)       │
└─────────────────────────────────┘
```

## File Structure

```
tmux-plugin/
├── scripts/
│   ├── navigator.sh          # Entry point
│   ├── navigator-list.sh     # Left pane (session list)
│   └── navigator-preview.sh  # Right pane (preview wrapper)
├── conf/
│   └── inner-tmux.conf       # Config for nested tmux
└── lib/
    └── common.sh             # Shared functions (updated)
```

## State Files

```
/tmp/claude-tower/
├── selected          # Currently selected session ID
├── caller            # Session to return to on quit
└── focus             # Current focus (list|preview)
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_TOWER_NAV_WIDTH` | 30 | Left pane width |
| `CLAUDE_TOWER_SOCKET` | claude-tower | Navigator server socket name |

### inner-tmux.conf

```bash
# No prefix - all keys pass through
set -g prefix None
set -g prefix2 None

# Escape detaches (returns to Navigator)
bind -n Escape detach-client

# Hide status bar for clean look
set -g status off

# Disable mouse (let outer tmux handle it)
set -g mouse off
```

## Error Handling

| Scenario | Handling |
|----------|----------|
| No sessions exist | Show "No sessions" message, offer to create |
| Selected session dies | Auto-refresh list, select next available |
| Navigator crashes | Can be reopened with prefix + t c |
| Default server not running | Show error, exit gracefully |

## Performance Considerations

1. **Session switching**: ~100ms (detach + attach)
2. **List refresh**: Every 2 seconds via timeout
3. **Preview update**: Real-time (native tmux)

## Security

- Navigator only reads from default server
- No special permissions required
- State files in /tmp with user permissions
