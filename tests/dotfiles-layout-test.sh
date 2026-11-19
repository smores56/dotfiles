#!/usr/bin/env bash
# Behavioural tests for scripts/link-dotfiles-checkout.sh. The script maintains
# ~/.dotfiles as a symlink to the dotfiles default worktree; it reports what it
# will not touch and never moves or replaces anything.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
script=$root/scripts/link-dotfiles-checkout.sh

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }

run() {
    DOTFILES_LINK=$1 DOTFILES_CHECKOUT=$2 sh "$script" >"$tmp/out" 2>&1
    rc=$?
    [ "$rc" -eq 0 ] || no "exit status $rc for link=$1"
    return 0
}

mkdir -p "$tmp/worktree/main" "$tmp/home"

# 1. The link is created and points at the worktree.
run "$tmp/home/.dotfiles" "$tmp/worktree/main"
if [ -L "$tmp/home/.dotfiles" ] \
        && [ "$(readlink "$tmp/home/.dotfiles")" = "$tmp/worktree/main" ]; then
    ok "creates the link to the worktree"
else
    no "creates the link to the worktree"
fi

# 2. A second run changes nothing and says nothing.
run "$tmp/home/.dotfiles" "$tmp/worktree/main"
if [ "$(readlink "$tmp/home/.dotfiles")" = "$tmp/worktree/main" ] \
        && ! grep -q 'linked' "$tmp/out"; then
    ok "leaves a correct link alone"
else
    no "leaves a correct link alone"
fi

# 3. A link pointing elsewhere is reported, not replaced.
mkdir -p "$tmp/other"
ln -s "$tmp/other" "$tmp/home/foreign"
run "$tmp/home/foreign" "$tmp/worktree/main"
if [ "$(readlink "$tmp/home/foreign")" = "$tmp/other" ] && grep -q 'points at' "$tmp/out"; then
    ok "reports a foreign link without replacing it"
else
    no "reports a foreign link without replacing it"
fi

# 4. A real directory in the way is never touched.
mkdir -p "$tmp/home/real/inner"
run "$tmp/home/real" "$tmp/worktree/main"
if [ -d "$tmp/home/real" ] && [ ! -L "$tmp/home/real" ] \
        && grep -q 'not a symlink' "$tmp/out"; then
    ok "reports a directory in the way without touching it"
else
    no "reports a directory in the way without touching it"
fi

# 5. A machine without the worktree (the work laptop) is a no-op.
run "$tmp/home/absent" "$tmp/missing/main"
if [ ! -e "$tmp/home/absent" ] && grep -q 'nothing to link' "$tmp/out"; then
    ok "does nothing when the worktree is absent"
else
    no "does nothing when the worktree is absent"
fi

# 6. An unwritable parent is reported, and nothing is created under it.
mkdir -p "$tmp/ro" && chmod 555 "$tmp/ro"
run "$tmp/ro/.dotfiles" "$tmp/worktree/main"
chmod 755 "$tmp/ro"
if [ ! -e "$tmp/ro/.dotfiles" ] && grep -q 'not writable' "$tmp/out"; then
    ok "creates nothing under an unwritable parent"
else
    no "creates nothing under an unwritable parent"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
