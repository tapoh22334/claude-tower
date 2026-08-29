# Claude Tower

> **Under development.** Rough edges and breaking changes are expected.

A tmux plugin for running several Claude Code sessions at once without losing
track of them.

Tower reads `~/.claude/projects/` and tracks the Claude sessions themselves,
not directories or worktrees — a session you started in a plain terminal
counts just as much as one Tower created. Once three or four are running, the
hard part is knowing which one is waiting on you, which is still thinking, and
which produced output you have not read.

```
┌─────────────────────────┬──────────────────────────────────────────┐
│ Sessions [ACTIVE]       │                                          │
│                         │  Claude Code session content             │
│ claude-tower ──── ⚡1    │  displayed here in real time             │
│ ⠹ fix the redraw bug    │                                          │
│ ▶ add queue view    ✱   │  Enter / i to type into it               │
│                         │  Escape to come back                     │
│ notes-app ──────────    │                                          │
│ ○ draft the outline     │                                          │
│                         │                                          │
│ j/k:nav ↵/i:input n:add │                                          │
└─────────────────────────┴──────────────────────────────────────────┘
       List (30%)                        View (70%)
```

Sessions group under their project. `⚡1` counts live `claude` processes in
that directory Tower does not manage yet; `✱` marks output you have not seen.

## Requirements

- tmux 3.2+
- Claude Code CLI (`claude`)
- fzf — recommended; the add flow falls back to a numbered prompt without it

## Installation

With [TPM](https://github.com/tmux-plugins/tpm), add to `~/.tmux.conf` and
press `prefix + I`:

```bash
set -g @plugin 'tapoh22334/claude-tower'
```

Or manually:

```bash
git clone https://github.com/tapoh22334/claude-tower ~/.tmux/plugins/claude-tower
# then in ~/.tmux.conf:
run-shell ~/.tmux/plugins/claude-tower/tmux-plugin/claude-tower.tmux
```

## Usage

`prefix + t` opens the Navigator. `j`/`k` moves, `Enter` or `i` types into the
highlighted session, `Escape` comes back.

| Key | Action |
|-----|--------|
| `j` / `k` | Move down / up |
| `g` / `G` | First / last |
| `Enter` / `i` | Type into the session |
| `Escape` | Back to the list |
| `n` | Add a session — pick a running one, or start a new one |
| `f` | Another session in the same directory (fresh conversation) |
| `N` | New session in a directory you pick |
| `D` | Unregister (the directory is left alone) |
| `r` | Resume a dormant session |
| `Tab` `t` `w` | Tile / Tail / Queue view |
| `?` `q` | Help / quit |

### Session states

| | | |
|---|---|---|
| `⠹` | Busy | Claude is working |
| `▶` | Active | Running, waiting for you |
| `○` | Dormant | Not running — press `r` |
| `◇` | External | Live outside Tower; use its own terminal |
| `✗` | Dead | Working directory is gone |
| `?` | Lost | Transcript is gone — press `D` |
| `✱` | Unread | New output since you last looked |

`⚙N` counts active subagents. Busy is inferred from transcript activity in a
45-second window, so a new session looks busy and a long tool call looks idle.

### The three multi-session views

**Tile** (`Tab`) — a grid of every session. Refreshes on `r`.
**Tail** (`t`) — sessions stacked, last few lines each, refreshing.
**Queue** (`w`) — only what is waiting on you, longest wait first.

Tile to choose, Tail to watch, Queue to work through. All return with `Enter`,
`Tab`, or `1`-`9`.

### Command line

```bash
tower add                      # open the picker
tower add .                    # start a session here, no prompts
tower add /path/to/project -n api   # ...somewhere else, with a name
tower rm <id>                  # unregister; the directory is untouched
```

`tower` lives at `tmux-plugin/scripts/tower`. Removing a session only drops
Tower's registry entry — the transcript survives, so `n` can re-add it.

## Configuration

```bash
# ~/.tmux.conf
set -g @tower-prefix 'T'          # default: t
```

```bash
export CLAUDE_TOWER_PROGRAM="claude"   # what a new session runs
export TOWER_FINDER="fzf --height=80% --reverse --no-multi"
export TOWER_BUSY_WINDOW=45            # seconds before busy → idle
export TOWER_LIST_MAX_WIDTH=80         # list content width bounds
export TOWER_LIST_MIN_WIDTH=50
```

<details>
<summary>Less common</summary>

```bash
export CLAUDE_TOWER_METADATA_DIR="$HOME/.claude-tower/metadata"
export CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
export CLAUDE_TOWER_NAV_SOCKET="claude-tower"
export CLAUDE_TOWER_SESSION_SOCKET="claude-tower-sessions"
export TOWER_TAIL_REFRESH=2            # tail/queue redraw interval
export TOWER_QUEUE_REFRESH=2
export TOWER_REBUILD_MIN_GAP=5         # quiet period between list rebuilds
export CLAUDE_TOWER_DEBUG=1            # verbose logging
```

</details>

## How it works

Tower runs its UI and your sessions on separate tmux servers, so it never
disturbs the tmux you were already using:

| Server | Socket | Role |
|--------|--------|------|
| Navigator | `claude-tower` | The UI |
| Session | `claude-tower-sessions` | Where Claude sessions run |
| Default | yours | Untouched |

It keeps almost no state. What a session *is* comes from Claude's own
transcript — whether it exists, when it was last active, its working
directory. Tower's registry only maps a `tower_<uuid>` to the Claude session
it came from, plus a name if you gave one. That is why unregistering never
destroys anything, and why a session started outside Tower can be adopted.

## Troubleshooting

```bash
make status    # servers, sessions, state files
make update    # pull the installed plugin and restart Navigator
make reset     # last resort — kills every running Claude session
```

A change that seems not to take effect is usually the plugin running from a
different copy than the one you edited; `tmux list-keys | grep tower` shows
which path is bound. Reloading tmux config alone does not restart a running
Navigator — use `make update`.

The log is at `~/.claude-tower/metadata/tower.log`, written always and never
rotated. `CLAUDE_TOWER_DEBUG=1` makes it verbose.

`make reset` kills both Tower servers, so **every running Claude session dies
with it**. Registrations survive as `○` dormant and `r` resumes them.

## License

MIT
