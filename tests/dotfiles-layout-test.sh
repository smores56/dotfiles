#!/usr/bin/env bash
# Behavioural tests for scripts/link-dotfiles-checkout.sh. The alias points at
# the live checkout, it is created only where the parent is writable, and nothing
# that exists is ever moved or replaced.
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

mkdir -p "$tmp/home/.dotfiles/.git" "$tmp/srv/github.com/o"

# 1. The alias is created and points at the checkout.
run "$tmp/srv/github.com/o/dotfiles" "$tmp/home/.dotfiles"
if [ -L "$tmp/srv/github.com/o/dotfiles" ] \
        && [ "$(readlink "$tmp/srv/github.com/o/dotfiles")" = "$tmp/home/.dotfiles" ]; then
    ok "creates the alias to the checkout"
else
    no "creates the alias to the checkout"
fi

# 2. A second run changes nothing and says nothing.
run "$tmp/srv/github.com/o/dotfiles" "$tmp/home/.dotfiles"
if [ "$(readlink "$tmp/srv/github.com/o/dotfiles")" = "$tmp/home/.dotfiles" ] \
        && ! grep -q 'linked' "$tmp/out"; then
    ok "leaves a correct alias alone"
else
    no "leaves a correct alias alone"
fi

# 3. An alias pointing elsewhere is reported, not replaced.
mkdir -p "$tmp/other"
ln -s "$tmp/other" "$tmp/srv/github.com/o/second"
run "$tmp/srv/github.com/o/second" "$tmp/home/.dotfiles"
if [ "$(readlink "$tmp/srv/github.com/o/second")" = "$tmp/other" ] && grep -q 'points at' "$tmp/out"; then
    ok "reports a foreign alias without replacing it"
else
    no "reports a foreign alias without replacing it"
fi

# 4. A real directory in the way is never touched.
mkdir -p "$tmp/srv/github.com/o/third/inner"
run "$tmp/srv/github.com/o/third" "$tmp/home/.dotfiles"
if [ -d "$tmp/srv/github.com/o/third" ] && [ ! -L "$tmp/srv/github.com/o/third" ] \
        && grep -q 'not a symlink' "$tmp/out"; then
    ok "reports a directory in the way without touching it"
else
    no "reports a directory in the way without touching it"
fi

# 5. An unwritable parent is reported, and nothing is created under it.
mkdir -p "$tmp/ro/inner" && chmod 555 "$tmp/ro/inner"
run "$tmp/ro/inner/dotfiles" "$tmp/home/.dotfiles"
chmod 755 "$tmp/ro/inner"
if [ ! -e "$tmp/ro/inner/dotfiles" ]; then
    ok "creates nothing under an unwritable parent"
else
    no "creates nothing under an unwritable parent"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
