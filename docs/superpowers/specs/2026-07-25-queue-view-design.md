# Queue view — sessions awaiting your action

2026-07-25. Backlog: TASK-7. Status: approved provisionally under full-auto
(user veto welcome).

## Problem

Running several Claude sessions at once, it is easy to lose track of which
ones are blocked on you: one finished and wants the next instruction,
another is stuck on a `[y/N]` permission prompt, a third is asking a
multiple-choice question. Tower's list view shows state per session but
does not answer "what should I attend to next, oldest first". The Queue
view does: one screen, every waiting session, longest wait on top.

Scope: **visualization only**. Summarizing a session and auto-answering
over tmux is explicitly out — a later, separate effort once detection is
proven. (Brainstorm decision.)

## Wait states (what counts as "waiting")

Four kinds, detected per session:

| kind          | meaning                                   | icon |
|---------------|-------------------------------------------|------|
| `permission`  | stopped on a `[y/N]` / "Do you want…" prompt | ⚠ |
| `question`    | stopped on a multiple-choice question (`❯ 1.`) | ？ |
| `input`       | finished, idle, waiting for the next prompt | ✱ |
| `error`       | process gone / crashed while registered   | ✗ |

A session that is actively working (`esc to interrupt` on screen, or
transcript touched within the busy window) is **not** waiting and does not
appear in the queue.

## Detection — two tiers

Claude writes `~/.claude/sessions/<pid>.json` per live process with a
`status` field (`idle`/`busy`), verified alive via `kill -0`. But `status`
alone cannot tell a permission prompt from a finished session — both read
`idle`. The distinguishing signal is on screen.

- **Tower-managed session** (has a pane on the session tmux server):
  `capture-pane` the last lines and classify by signature. Verified
  against live panes:
  - `esc to interrupt` → working, skip.
  - `Do you want` / `[y/N]` / `❯ 1.` near a `Yes/No` → `permission`.
  - `❯ 1.` with a numbered list (no yes/no) → `question`.
  - none of the above, process idle → `input`.
- **Tower-external session** (live pid, no managed pane — a fork or plain
  terminal): the pane is unreachable, so classify coarsely: idle → `input`
  (labelled so the user knows it is a guess). Never claim a precise
  permission/question state we cannot see.
- **Registered but no live process, cwd/transcript intact** → not waiting
  (dormant); excluded from the queue. **cwd or transcript gone** → `error`.

`get_wait_state <session_id>` returns one of the four kinds or empty (not
waiting). `wait_since <session_id>` returns the epoch the wait began —
approximated by the newest activity timestamp already computed by
`get_session_activity` (the moment work stopped ≈ when the wait started).

## Ordering

By wait duration, **longest first** (`now - wait_since`, descending). The
point is to surface what has been ignored longest. (Brainstorm decision.)

## UI

New view `queue-view.sh`, modeled on `tail-view.sh` (same alt-screen
frame, atomic redraw that never overflows height, capped width, same
quit/return handoff). Entered with **`w`** ("waiting") from the list view.
Auto-refreshes on the tail cadence so ages tick and new waits appear.

Row: `<icon> <label>   <age>` — wait-kind icon, the session's title label
(reusing `_session_label`'s truncation/width logic), and a right-aligned
relative age (`3m` / `1h` / `2d`) in a fixed column, like the list view's
status column. Empty queue shows "Nothing waiting — all caught up.".

Keys match tile/tail: `j/k` move, `g/G` first/last, `1-9` pick + return to
list, `Enter`/`Tab` return keeping selection, `q` quit. Selecting returns
to the list view focused on that session (`set_nav_selected` + attach) so
the very next action is to press `i` and answer it.

## Files

- `tmux-plugin/lib/claude-sessions.sh`: `get_wait_state`, `wait_since`,
  and a `capture_pane_signature` helper isolated so tests can stub it.
- `tmux-plugin/scripts/queue-view.sh`: the view (sourcing guard so bats
  can test its pure `build_queue_frame` / ordering directly).
- `tmux-plugin/scripts/navigator-list.sh`: `switch_to_queue`, `w` key,
  help + footer entry.

## Testing

bats, fresh-subprocess where common.sh is involved:
- `get_wait_state` classification for each signature (stubbed capture).
- `esc to interrupt` → empty (working, not waiting).
- external session (no pane) → coarse `input`, never permission/question.
- queue ordering: three waits with different `wait_since` sort
  longest-first.
- `build_queue_frame`: height budget holds, last line no trailing newline,
  empty-queue message.
- `w` key wired; row shows icon + age.
Full suite via `make test-docker`.
