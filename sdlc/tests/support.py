import os
import stat
import subprocess
import sys

MODULE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CLI = os.path.join(MODULE_DIR, "sdlc_issues.py")
sys.path.insert(0, MODULE_DIR)

DESIGN = (
    "## Problem\n\n"
    "Features drift from the approved design and merged code.\n\n"
    "## Design\n\n"
    "Use GitHub issues.\n\n"
    "### Principles\n\n"
    "1. One issue per feature.\n\n"
    "## Plan\n\n"
    "- [ ] T1: Build\n"
)
DESIGN_SHA = "a7c00c28e002380560f62e5ddc98968e2b93784ce57a4fc79152353d284bffcc"
COMMENT_AT = "2026-10-20T12:00:00Z"


def write_script(bin_dir, name, source):
    path = os.path.join(bin_dir, name)
    with open(path, "w") as fh:
        fh.write(source.replace("{python}", sys.executable))
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR | stat.S_IXGRP)
    return path


def run_cli(args, env, stdin=None):
    return subprocess.run(
        [sys.executable, CLI, *args],
        capture_output=True,
        text=True,
        env=env,
        input=stdin,
        stdin=subprocess.DEVNULL if stdin is None else None,
    )
