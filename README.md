# Claude Tower

A tmux plugin for running several Claude Code sessions at once without losing
track of them.

Tower tracks the Claude sessions themselves, reading `~/.claude/projects/`
rather than managing directories or worktrees. Any session counts — one you
started in a plain terminal, one Claude forked, one from last week — so
nothing you were working on is invisible to it.

The problem it solves is attention. Once three or four sessions are running,
the hard part is no longer starting them: it is knowing which one is waiting
on you, which is still thinking, and which produced output you have not read.

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

Sessions group under the project they belong to. The `⚡1` on a group header
counts live `claude` processes in that directory that Tower does not manage
yet; `✱` marks output you have not seen since you last visited.

## Requirements

- tmux 3.2+
- Claude Code CLI (`claude`)
- fzf — recommended; the add flow falls back to a numbered prompt without it
- git — optional, only for creating a worktree from the new-session prompt

## Installation

With [TPM](https://github.com/tmux-plugins/tpm):

```bash
set -g @plugin 'tapoh22334/claude-tower'
```

Press `prefix + I` to install.

Manually:

```bash
git clone https://github.com/tapoh22334/claude-tower ~/.tmux/plugins/claude-tower
```

Then add to `~/.tmux.conf`:

```bash
run-shell ~/.tmux/plugins/claude-tower/tmux-plugin/claude-tower.tmux
```

## Usage

`prefix + t` opens the Navigator. `j`/`k` moves, `Enter` or `i` drops you into
the highlighted session, `Escape` brings you back to the list.

### Keys

| Key | Action |
|-----|--------|
| `j` / `k` (or `↓` / `↑`) | Move down / up |
| `g` / `G` | Jump to first / last |
| `Enter` / `i` | Focus the view pane and type into the session |
| `Escape` | Return to the list |
| `n` | Add a session — pick a running Claude session, or start a new one |
| `f` | Start another session in the selected session's directory (a fresh conversation, not a copy of it) |
| `N` | Start a new session in a directory you pick |
| `D` | Unregister the session (the directory is left alone) |
| `r` | Resume a dormant session |
| `Tab` | Tile view |
| `t` | Tail view |
| `w` | Queue view |
| `?` | Help |
| `q` | Quit |

### Adding sessions

`n` lists the Claude sessions on your machine that Tower does not know about
yet — anything with a real conversation and a directory that still exists —
plus a `[new]` entry. Picking an existing one adopts it; picking `[new]` asks
for a directory and an optional name.

At that directory prompt, a path that does not exist offers to create it, and
typing `+` instead walks you through `git worktree add` (repository, worktree
path, branch — defaulting to `tower/<name>`). Tower does not track or remove
the worktrees it helps you create; that stays your job.

### Session states

| Mark | State | Meaning |
|------|-------|---------|
| `⠹` | Busy | Claude is working — a turning spinner in the live list |
| `▶` | Active | Running, waiting for you |
| `○` | Dormant | Registered but not running — press `r` |
| `◇` | External | A live `claude` outside Tower; attach from its own terminal |
| `✗` | Dead | The session's working directory is gone |
| `?` | Lost | The transcript is gone — unrecoverable, press `D` to clear |
| `✱` | Unread | New output since you last looked at this session |

A `⚙N` beside a row counts that session's active subagents.

Busy is inferred from how recently the transcript changed, within a 45-second
window (`TOWER_BUSY_WINDOW`). Two consequences worth knowing: a session looks
busy for its first 45 seconds, and a tool call that runs longer than that
looks idle while it works.

### Seeing several sessions at once

Three views answer three different questions, all reachable from the list and
all returning to it with `Enter`, `Tab`, or a number key `1`-`9`:

**Tile** (`Tab`) — every session in a grid. The overview: what is running,
roughly where each one is. Refreshes when you press `r`, not on its own.

**Tail** (`t`) — sessions stacked vertically, each showing its last few lines,
refreshing continuously. Use it to watch work happen across sessions.

**Queue** (`w`) — only the sessions waiting on you, longest wait first. Use it
to decide what to answer next; nothing blocked gets forgotten at the bottom of
a long list. Each row says what kind of wait it is: `⚠` a permission prompt,
`？` a numbered choice, `✱` finished and idle, `✗` broken.

In short: Tile to choose, Tail to watch, Queue to work through.

### From the command line

The `tower` script (at `tmux-plugin/scripts/tower`) works outside the
Navigator. Put it on your `PATH` to use it directly.

```bash
tower add            # open the picker to add a session
tower rm <id>        # unregister a session; the directory is untouched
tower rm <id> -f     # ...without the confirmation prompt
```

`tower add` opens the same picker as `n` — it does not yet take a path or a
name as arguments, despite what its own `--help` currently suggests.

Removing a session only drops Tower's registry entry. The Claude transcript
survives, so you can re-add the session with `n` until Claude's own cleanup
removes it after about 30 days.

## Configuration

The prefix key is a tmux option:

```bash
# ~/.tmux.conf — change the tower prefix key (default: t)
set -g @tower-prefix 'T'
```

Everything else is an environment variable. The ones worth knowing:

```bash
# Program to run for a new session (default: claude)
export CLAUDE_TOWER_PROGRAM="claude"

# Command used to pick a session or directory in the add flow. Falls back to a
# numbered prompt if the binary isn't found.
export TOWER_FINDER="fzf --height=80% --reverse --no-multi"

# Seconds since the last transcript activity before a running session counts
# as idle rather than busy (default: 45)
export TOWER_BUSY_WINDOW=45

# Bounds on how wide the list draws its content. The list pane itself is a
# fixed 30% split; these clamp the text inside it.
export TOWER_LIST_MAX_WIDTH=80
export TOWER_LIST_MIN_WIDTH=50
```

<details>
<summary>Less common settings</summary>

```bash
# Where Tower keeps its registry (default: ~/.claude-tower/metadata)
export CLAUDE_TOWER_METADATA_DIR="$HOME/.claude-tower/metadata"

# Where Claude's transcripts are read from (default: ~/.claude/projects)
export CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"

# tmux socket names for Tower's two servers
export CLAUDE_TOWER_NAV_SOCKET="claude-tower"
export CLAUDE_TOWER_SESSION_SOCKET="claude-tower-sessions"

# How often the tail and queue views redraw, in seconds (default: 2)
export TOWER_TAIL_REFRESH=2
export TOWER_QUEUE_REFRESH=2

# Verbose logging to ~/.claude-tower/metadata/tower.log
export CLAUDE_TOWER_DEBUG=1
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

It keeps almost no state of its own. What a session *is* comes from Claude's
own transcript at `~/.claude/projects/<slug>/<sessionId>.jsonl` — whether it
exists, when it was last active, and its working directory. Tower's registry
at `~/.claude-tower/metadata/*.meta` only maps a `tower_<uuid>` to the Claude
session it was registered from, plus a name if you gave it one.

That is why unregistering a session never destroys anything, and why a session
started outside Tower can be adopted at any time.

## Troubleshooting

Start with:

```bash
make status    # servers, sessions, and state files
```

If the plugin does not seem loaded, reload tmux's config and check the binding
exists:

```bash
tmux source ~/.tmux.conf
tmux list-keys | grep tower
```

If `prefix + t` does nothing, confirm your tmux is 3.2 or newer (`tmux -V`).

**A change that does not seem to take effect** is usually the plugin running
from a different copy than the one you edited — `tmux list-keys | grep tower`
shows which path is actually bound. If you installed with TPM, update with:

```bash
make update    # pull the installed plugin, then kill Navigator so it reloads
```

Reloading tmux's config alone does not restart an already-running Navigator.

When the cause is not obvious, the log is at
`~/.claude-tower/metadata/tower.log` — written always, not only in debug mode,
and never rotated, so delete it yourself if it grows. `CLAUDE_TOWER_DEBUG=1`
makes it verbose.

As a last resort:

```bash
make reset
```

This kills both of Tower's servers, so **every running Claude session is
terminated**. Registrations survive — the sessions come back as `○` dormant
and `r` resumes them — but unread marks are cleared along with the rest of
Tower's state under `/tmp/claude-tower`. Your own tmux server is untouched.

## Migrating from v3.x

Tower used to manage directories and worktrees; it now tracks Claude sessions.

Existing worktrees keep working — press `n` and pick the session running
there. Tower no longer deletes worktrees or branches when you remove a
session, so clean those up yourself with `git worktree remove` and
`git branch -d`. Old registry entries with non-UUID names show up as `?` and
can be cleared with `D`. Note that Claude deletes its transcripts after about
30 days, so sessions older than that can no longer be adopted.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports are most useful with your
tmux version, what you pressed, and the tail of `tower.log`.

## License

MIT
