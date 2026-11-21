#!/usr/bin/env python3
"""Render the screensaver at fixed pane sizes and report whether the tree fits.

The renderer prints one line per row after leaving curses, so the tree's ink is
easy to measure: split at the last alternate-screen leave, strip ANSI, and look
at the first rows-1 lines. A tree touching an edge means the life formula is too
generous for that pane.

usage: tests/cbonsai-fit.py [SCREENSAVERS] [CBONSAI]
"""

import fcntl
import os
import pty
import re
import select
import struct
import subprocess
import sys
import termios

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCREENSAVERS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "home/.local/bin/screensavers")
CBONSAI = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/.local/bin/cbonsai")

ANSI = re.compile(r"\x1b\[[0-9;?-]*[A-Za-z]|\x1b[()][A-Za-z0-9]|\x1b>|\r")


def life(rows, cols):
    return int(subprocess.check_output([SCREENSAVERS, "--life", str(rows), str(cols)], text=True))


def render(rows, cols, seed):
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    env = dict(os.environ, TERM="xterm-256color", LINES=str(rows - 1), COLUMNS=str(cols))
    proc = subprocess.Popen(
        [CBONSAI, "-p", "-L", str(life(rows, cols)), "-s", str(seed)],
        stdin=slave, stdout=slave, stderr=slave, env=env, close_fds=True,
    )
    os.close(slave)
    data = b""
    while True:
        ready, _, _ = select.select([master], [], [], 10)
        if not ready:
            break
        try:
            chunk = os.read(master, 65536)
        except OSError:
            break
        if not chunk:
            break
        data += chunk
    proc.wait(timeout=10)
    os.close(master)
    text = data.decode("utf-8", "replace")
    # printstdscr() runs after endwin(); everything before is the curses screen.
    return ANSI.sub("", text.rsplit("\x1b[?1049l", 1)[-1])


def box(lines, rows, cols):
    ink = [(y, x) for y, line in enumerate(lines[: rows - 1]) for x, ch in enumerate(line[:cols]) if ch != " "]
    if not ink:
        return None
    ys = [p[0] for p in ink]
    xs = [p[1] for p in ink]
    # Line width varies: use the widest line for the right edge.
    width = max((len(line) for line in lines[: rows - 1]), default=0)
    return min(ys), max(ys), min(xs), max(xs), width


def main():
    failures = 0
    for rows, cols in ((24, 80), (40, 120), (50, 200), (18, 40)):
        for seed in range(1, 11):
            lines = render(rows, cols, seed).split("\n")
            found = box(lines, rows, cols)
            if not found:
                print(f"FAIL {rows}x{cols} seed={seed}: no ink")
                failures += 1
                continue
            top, bottom, left, right, width = found
            clipped = []
            if top == 0:
                clipped.append("top")
            if right >= cols - 1:
                clipped.append("right")
            if left == 0:
                clipped.append("left")
            if width > cols:
                clipped.append(f"line>{cols}")
            if clipped:
                failures += 1
            print(
                f"{'FAIL' if clipped else 'ok  '} {rows}x{cols} seed={seed:2d} "
                f"life={life(rows, cols):3d} box=({top},{bottom},{left},{right}) "
                f"w={right - left + 1} {','.join(clipped)}"
            )
    print(f"{failures} clipped renders")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
