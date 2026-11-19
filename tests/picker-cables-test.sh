#!/usr/bin/env bash
# Behavioural tests for the television cables: the repos picker opens a
# repository's default worktree, and the worktrees picker labels the siblings
# of the bare gitdir. Hermetic: a fake ghq and a local fixture, no network.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cables=$root/home/.config/television/cable
for tool in python3 git; do
    command -v "$tool" >/dev/null 2>&1 || {
        printf 'skip picker cable tests (%s not installed)\n' "$tool"
        exit 0
    }
done

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
assert() {  # assert <desc> <command...>
    local desc=$1
    shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else no "$desc"; fi
}

source_command() {
    python3 -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["source"]["command"])' "$1"
}

# --- fixture ----------------------------------------------------------------

git init -q --bare "$tmp/seed.git"
git -C "$tmp/seed.git" symbolic-ref HEAD refs/heads/main
git clone -q "$tmp/seed.git" "$tmp/src"
git -C "$tmp/src" -c user.email=a@b -c user.name=a commit -q --allow-empty -m one
git -C "$tmp/src" push -q origin HEAD:main

repo=$tmp/root/github.com/o/r
mkdir -p "$repo"
git clone -q --bare "$tmp/seed.git" "$repo/.git"
git -C "$repo" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git -C "$repo" worktree add -q "$repo/main" main
git -C "$repo/main" fetch -q origin
git -C "$repo" worktree add -q "$repo/add-gizmo" -b smores/add-gizmo origin/main

# A normal clone (the work-laptop shape) with a source directory named main.
normal=$tmp/root/github.com/o/normal
git clone -q "$tmp/seed.git" "$normal"
mkdir -p "$normal/main"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/ghq" <<EOF
#!/bin/sh
[ "\$1" = list ] || exit 9
printf '%s\\n' "$repo" "$normal"
EOF
chmod +x "$tmp/bin/ghq"

# --- repos picker -----------------------------------------------------------

repos_cmd=$(source_command "$cables/repos.toml")
repos_out=$(PATH="$tmp/bin:$PATH" sh -c "$repos_cmd") || no "the repos cable exits 0"
assert "the repos picker opens the default worktree" \
    grep -qxF "$repo/main" <<<"$repos_out"
assert "a normal clone is not mistaken for a clean-bare worktree" \
    grep -qxF "$normal" <<<"$repos_out"
assert "a source directory named main is not appended" \
    bash -c '! grep -qxF "$1" <<<"$2"' _ "$normal/main" "$repos_out"

# --- worktrees picker -------------------------------------------------------

worktrees_cmd=$(source_command "$cables/worktrees.toml")
want=$(printf '%s\n%s\n' "add-gizmo	$repo/add-gizmo" "main	$repo/main" | sort)
for where in "$repo/main" "$repo"; do
    got=$(cd "$where" && sh -c "$worktrees_cmd" | sort) \
        || no "the worktrees cable exits 0 from $where"
    assert "the worktrees picker labels the siblings from $(basename "$where")" \
        test "$got" = "$want"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
