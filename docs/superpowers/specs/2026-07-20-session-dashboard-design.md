# Session dashboard — grouping, external visibility, quick starts

2026-07-20. Status: approved provisionally under full-auto (user veto welcome).

## Requests (user)

1. Group sessions by project in the Navigator list.
2. Visualize subagents and Claude sessions running outside Tower
   ("fork" = another session on the same project, possibly started
   elsewhere).
3. Start a new session in the same directory as an existing one.
4. Start a new session by picking a directory.

## Data sources (all already on disk, no new state)

- `~/.claude/sessions/<pid>.json` — one file per **live** claude process:
  `sessionId`, `cwd`, `status`. Liveness = `kill -0 <pid>`. This is how
  Tower sees sessions running outside its tmux servers.
- `<projects>/<slug>/<sessionId>/subagents/*.jsonl` — subagent
  transcripts; one is "active" if its mtime is within TOWER_BUSY_WINDOW.
- Transcript `cwd` — already used for labels; becomes the group key.

## Design

### 1. Grouped list view

`build_session_list` sorts normal (busy/active/dormant/external) sessions
by project dir, preserving `list_all_sessions` order within a group, and
records each row's group. `render_list` emits a dim `▍dirname` header row
whenever the group changes. Body lines are composed into an array first so
the height budget and `+N more` stay exact (headers consume budget too).
Broken (dead/lost) sessions stay in the trailing "unrecoverable" section,
ungrouped, as today.

Because the group header now carries the directory name, the per-row label
changes from `dirname (name)` to `conversation title (name)` (via
`get_session_title`, truncated), falling back to the short id — same
information hierarchy as the add picker.

### 2. External sessions and subagents

- New display state `external` (icon `◇`): registered, no tmux session,
  transcript and cwd intact, **and** a live claude process has its
  sessionId. Today this renders as dormant, and `r` would resume a second
  copy of a session that is already running elsewhere — the resume guard
  now rejects external sessions with a clear message.
- Busy rows get a `⚙N` suffix when N subagent transcripts are active.
- Group headers show `⚡N` when N live claude processes run in that
  directory **unregistered** (e.g. forks started outside Tower). They are
  intentionally not selectable rows: Tower cannot attach to them (they own
  their tty); registering them stays the add picker's job.

### 3. `f` — fork here

`f` on a selected session starts a **new** Claude session in the same
directory: generate a UUID, `start_claude_session tower_<uuid> <cwd> new`,
register, select it. No prompts.

### 4. `N` — pick a directory and start

`N` runs `session-add.sh --new-in-dir --print-id`: a picker (fzf/numbered,
same machinery as `n`) over known project directories — every distinct
transcript cwd that still exists, newest activity first — then starts a
session there. No name prompt (rename later via registry if wanted).

Footer becomes:
`j/k:nav Enter/i:input n:add f:fork N:new-dir D:del r:resume t:tail q:quit`

## Testing

bats (fresh-subprocess pattern where common.sh is involved):
- `list_live_claude_processes`: stub dir with a live-pid json (use $$) and
  a dead-pid json → only live one listed, fields parsed.
- `get_display_state`: external vs dormant switched by process liveness.
- `count_active_subagents`: fresh vs old subagent transcripts.
- grouped render: header rows appear once per dir; height budget holds
  with headers (30 sessions / 12 lines, SENTINEL last-line test).
- `f`/`N` key wiring + `list_project_dirs` ordering.
Full suite via `make test-docker` only.
