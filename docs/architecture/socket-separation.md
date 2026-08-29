# Navigator Architecture - Socket Separation Design

## Overview

Tower runs on two tmux servers of its own — one for the Navigator UI, one for
the Claude sessions — and leaves the user's default server alone. The UI can
crash without taking the sessions with it, and killing Tower never touches the
tmux the user was already working in.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│ -L claude-tower-sessions (where the work happens)               │
│                                                                 │
│ ├── tower_api        ← Claude Code session                     │
│ ├── tower_frontend   ← Claude Code session                     │
│ ├── tower_scripts    ← Claude Code session                     │
│ └── tower-tile / tower-tail / tower-queue  ← view windows      │
└─────────────────────────────────────────────────────────────────┘
        ▲
        │ Right pane connects via: TMUX= tmux -L … attach -t <session>
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
│     │   tower_frontend│ (Attached to session server)         │  │
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

Three servers, not two. Claude sessions moved off the user's default server
onto one of Tower's own, so that killing Tower cannot take the user's tmux
with it and vice versa.

| Server | Socket | Purpose |
|--------|--------|---------|
| default | `/tmp/tmux-{UID}/default` | The user's own sessions. Tower never touches it except to return you there |
| claude-tower | `/tmp/tmux-{UID}/claude-tower` | The Navigator UI |
| claude-tower-sessions | `/tmp/tmux-{UID}/claude-tower-sessions` | Where Claude sessions actually run |

Both Tower socket names are overridable — `CLAUDE_TOWER_NAV_SOCKET` and
`CLAUDE_TOWER_SESSION_SOCKET` (`lib/common.sh`).

### Components

1. **navigator.sh**: Entry point, manages Navigator lifecycle
2. **navigator-list.sh**: Left pane, session list with vim-style navigation
3. **navigator-view.sh**: Right pane wrapper. Runs a nested tmux client
   attached to the selected session on the session server — which is why
   you can read a session and type into it in place
4. **view-focus.conf**: Configuration for the nested tmux client

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
│    - Right: navigator-view.sh   │
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
│ 3. Get view pane's tty          │
│    #{pane_tty} → /dev/ttysXXX   │
│ 4. Switch inner tmux client     │
│    TMUX= tmux switch-client     │
│    -c /dev/ttysXXX -t $session  │
└─────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────┐
│ Inner tmux client instantly     │
│ switches to new session         │
│ (no detach/re-attach cycle)     │
└─────────────────────────────────┘
```

Note: Using `switch-client` provides instant session switching without
detach/re-attach cycles, providing a smoother user experience.

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
│ 3. User navigates back          │
│    - prefix + arrow to list     │
│    - j/k triggers focus:list    │
│    - View re-attaches with -r   │
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
│    on the session server         │
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
│   └── navigator-view.sh     # Right pane (view wrapper)
├── conf/
│   └── view-focus.conf       # Config for nested tmux
└── lib/
    └── common.sh             # Shared functions
```

## State Files

```
/tmp/claude-tower/
├── selected          # Currently selected session ID
├── caller            # Session to return to on quit
└── focus             # Current focus (list|view)
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_TOWER_NAV_SOCKET` | claude-tower | Navigator server socket name |
| `CLAUDE_TOWER_SESSION_SOCKET` | claude-tower-sessions | Session server socket name |

The list pane is a fixed 30% split; `TOWER_LIST_MAX_WIDTH` /
`TOWER_LIST_MIN_WIDTH` bound the text drawn inside it. See the README for the
full set.

### View Mode Control

View pane always attaches in input mode (no `-r` flag). Pane focus determines whether the user can interact with the session:

- **List pane focused**: User navigates sessions with j/k keys
- **View pane focused**: User can type directly into the Claude Code session (activated with `i` key)

Session switching uses `switch-client` for instant transitions without detach/re-attach cycles.

## Error Handling

| Scenario | Handling |
|----------|----------|
| No sessions exist | Show "No sessions" message, offer to create |
| Selected session dies | Auto-refresh list, select next available |
| Navigator crashes | Can be reopened with prefix + t c |
| Default server not running | Show error, exit gracefully |

## Performance Considerations

1. **Session switching**: Instant (switch-client, no detach/attach cycle)
2. **List refresh**: Every 2 seconds via timeout
3. **Preview update**: Real-time (native tmux)

## Security

- Navigator never writes to the user's own tmux server
- No special permissions required
- State files in /tmp with user permissions
