#!/usr/bin/env python3
"""Run a command with a controlling pseudo-terminal and relay stdout.

`zsh -i -c` under CI has no terminal, so compinit aborts before the plugins
under test load. This gives the child a real controlling terminal while stdout
is still captured and stderr stays where the caller redirected it.

usage: pty-run.py <command> [args...]
"""

import fcntl
import os
import pty
import struct
import sys
import termios

if len(sys.argv) < 2:
    sys.exit("usage: pty-run.py <command> [args...]")

master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))

pid = os.fork()
if pid == 0:
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    os.close(master)
    os.dup2(slave, 0)
    os.dup2(slave, 1)
    os.close(slave)
    os.execvp(sys.argv[1], sys.argv[1:])

os.close(slave)
out = b""
while True:
    try:
        chunk = os.read(master, 65536)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
os.close(master)
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf-8", "replace").replace("\r\n", "\n"))
sys.exit(os.waitstatus_to_exitcode(status))
