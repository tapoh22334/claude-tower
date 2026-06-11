#!/usr/bin/env python3
"""Attach a real, fixed-size tmux client over a PTY.

The headless tests (`new-session -d` + capture-pane) can assert structure and
content, but they have no attached client — so they cannot reproduce the
behaviours that only happen when a client of a definite size is present:
window sizing, resize negotiation, the marching pane-shrink that the old
nested-attach Tile suffered, or client-detached hooks.

This helper spawns `tmux attach` inside a PTY whose window size we pin to
COLS x ROWS, then drains the master so the client never blocks on output.
It runs until killed (SIGTERM/SIGINT from the test's teardown), at which point
the PTY closes and the client detaches cleanly.

With an optional input FIFO it also becomes a *driver*: any bytes written to
the FIFO are forwarded to the client's PTY as if typed, so a test can press
real keys (e.g. the prefix C-b then Tab) and exercise tmux key bindings the
way a human would — the terminal equivalent of a browser test clicking a
button. Writing raw control bytes is enough: `printf '\\002\\t' > "$fifo"`
sends prefix+Tab.

Usage:
    pty_client.py <socket> <target-session> <cols> <rows> [input-fifo]

Run it in the background from a test, capture the PID, and kill it in teardown.
Requires only the Python standard library (no `expect`).
"""
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios


def main() -> int:
    if len(sys.argv) not in (5, 6):
        sys.stderr.write(
            "usage: pty_client.py <socket> <target> <cols> <rows> [input-fifo]\n"
        )
        return 2
    socket, target = sys.argv[1], sys.argv[2]
    cols, rows = int(sys.argv[3]), int(sys.argv[4])
    input_fifo = sys.argv[5] if len(sys.argv) == 6 else None

    pid, master_fd = pty.fork()
    if pid == 0:
        # Child: the slave PTY is now our controlling terminal (fd 0/1/2).
        # Pin its window size BEFORE exec so tmux reports COLS x ROWS.
        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(0, termios.TIOCSWINSZ, winsize)
        env = dict(os.environ)
        env.pop("TMUX", None)  # never inherit an outer tmux
        # tmux refuses to attach under a terminal whose terminfo lacks `clear`
        # (headless CI containers default to TERM=dumb). Force a sane TERM with
        # standard terminfo; keep a real inherited TERM for local runs.
        if env.get("TERM", "") in ("", "dumb", "unknown", "network"):
            env["TERM"] = "xterm"
        os.execvpe(
            "tmux",
            ["tmux", "-L", socket, "attach-session", "-t", target],
            env,
        )
        os._exit(127)  # unreachable unless exec fails

    # Parent: keep the client alive by draining its output until we are
    # signalled, then tear the PTY down so the client detaches.
    stop = {"flag": False}

    def _stop(_signum, _frame):
        stop["flag"] = True

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    # Open the input FIFO O_RDWR so we are always also a writer: the reader end
    # then never sees EOF when a test's `printf > fifo` writer closes, so a
    # single client can receive many separate key bursts.
    fifo_fd = None
    if input_fifo:
        fifo_fd = os.open(input_fifo, os.O_RDWR | os.O_NONBLOCK)

    watch = [master_fd] + ([fifo_fd] if fifo_fd is not None else [])
    while not stop["flag"]:
        try:
            readable, _, _ = select.select(watch, [], [], 0.5)
        except InterruptedError:
            continue
        if fifo_fd is not None and fifo_fd in readable:
            try:
                keys = os.read(fifo_fd, 4096)
                if keys:
                    os.write(master_fd, keys)  # inject as typed input
            except OSError:
                pass
        if master_fd in readable:
            try:
                if not os.read(master_fd, 8192):
                    break  # client exited on its own
            except OSError:
                break

    if fifo_fd is not None:
        try:
            os.close(fifo_fd)
        except OSError:
            pass
    try:
        os.close(master_fd)
    except OSError:
        pass
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
