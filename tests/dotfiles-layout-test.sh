#!/usr/bin/env bash
# scripts/link-dotfiles-checkout.sh keeps ~/.dotfiles a symlink to the default
# worktree; it reports what it will not touch, exits 1 for it, and never moves or
# replaces anything.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

script=$root/scripts/link-dotfiles-checkout.sh

run() {  # run <want-status> <link> <checkout>
    DOTFILES_LINK=$2 DOTFILES_CHECKOUT=$3 sh "$script" >"$tmp/out" 2>&1
    expect "exit status for link=$2" "$1" "$?"
}
said() { grep -q "$1" "$tmp/out"; }

mkdir -p "$tmp/worktree/main" "$tmp/home"
: >"$tmp/worktree/main/.git"

run 0 "$tmp/home/.dotfiles" "$tmp/worktree/main"
expect "creates the link to the worktree" "$tmp/worktree/main" "$(readlink "$tmp/home/.dotfiles")"

run 0 "$tmp/home/.dotfiles" "$tmp/worktree/main"
expect "leaves a correct link alone" "$tmp/worktree/main" "$(readlink "$tmp/home/.dotfiles")"
assert_not "a correct link is not relinked" said linked

mkdir -p "$tmp/other"
ln -s "$tmp/other" "$tmp/home/foreign"
run 1 "$tmp/home/foreign" "$tmp/worktree/main"
expect "a foreign link is not replaced" "$tmp/other" "$(readlink "$tmp/home/foreign")"
assert "a foreign link is reported" said 'points at'

mkdir -p "$tmp/home/real/inner"
run 1 "$tmp/home/real" "$tmp/worktree/main"
assert "a directory in the way is untouched" test -d "$tmp/home/real" -a ! -L "$tmp/home/real"
assert "a directory in the way is reported" said 'not a symlink'

# The work laptop has no worktree.
run 0 "$tmp/home/absent" "$tmp/missing/main"
assert_not "nothing is linked when the worktree is absent" test -e "$tmp/home/absent"
assert "an absent worktree is reported" said 'nothing to link'

mkdir -p "$tmp/empty/main"
run 0 "$tmp/home/empty" "$tmp/empty/main"
assert_not "nothing is linked when the target is not a checkout" test -e "$tmp/home/empty"
assert "a target that is not a checkout is reported" said 'no checkout'

mkdir -p "$tmp/ro" && chmod 555 "$tmp/ro"
run 1 "$tmp/ro/.dotfiles" "$tmp/worktree/main"
chmod 755 "$tmp/ro"
assert_not "nothing is created under an unwritable parent" test -e "$tmp/ro/.dotfiles"
assert "an unwritable parent is reported" said 'not writable'

finish
