#!/usr/bin/env bash
# Behavioral tests for the `git get` alias as the identity environment renders
# it. Hermetic: the rendered alias runs against a fixture remote that git
# reaches through url.insteadOf, under a throwaway root. Needs mise and git.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
mise_bin=${MISE_BIN:-$(command -v mise || true)}
if [ -z "$mise_bin" ]; then
    printf 'skip git get tests (mise not installed)\n'
    exit 0
fi

tmp=$(cd -P -- "$(mktemp -d)" && pwd) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
expect() {  # expect <desc> <want> <got>
    if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$2', got '$3')"; fi
}

h=$tmp/home
mkdir -p "$h/.ssh"
env -i HOME="$h" PATH=/usr/bin:/bin TERM=dumb MISE_ENV=identity \
    MISE_TRUSTED_CONFIG_PATHS="$root" MISE_YES=1 \
    "$mise_bin" -C "$root" dot apply >"$tmp/apply.log" 2>&1 \
    || { no "identity applies"; sed 's/^/     /' "$tmp/apply.log" >&2; }

alias_text=$(git config -f "$h/.config/git/machine.inc" alias.get)
expect "the alias clones under the personal root" yes \
    "$([[ $alias_text == *'d=/srv/git/github.com/'* ]] && echo yes || echo no)"

# The same alias under a throwaway root, against a fixture with two branches.
repos=$tmp/repos
git init -q -b main "$tmp/up"
git -C "$tmp/up" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one
git -C "$tmp/up" branch feat
mkdir -p "$tmp/fake/o"
git clone -q --bare "$tmp/up" "$tmp/fake/o/r"
# Every personal checkout is a linked worktree, where git exports GIT_DIR to
# aliases, so git get runs from inside one.
git -C "$tmp/up" worktree add -q "$tmp/caller" feat
get() {  # get <args...>: the rendered alias, root and GitHub redirected
    cd "$tmp/caller" && env -i HOME="$tmp" PATH=/usr/bin:/bin GIT_CONFIG_NOSYSTEM=1 \
        GIT_CONFIG_COUNT=3 \
        GIT_CONFIG_KEY_0=alias.get GIT_CONFIG_VALUE_0="${alias_text//\/srv\/git/$repos}" \
        GIT_CONFIG_KEY_1="url.file://$tmp/fake/.insteadOf" GIT_CONFIG_VALUE_1=https://github.com/ \
        GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=t@t \
        git get "$@"
}

repo=$repos/github.com/o/r
get o/r >"$tmp/get.log" 2>&1
rc=$?
expect "git get exits 0" 0 "$rc"
[ "$rc" -eq 0 ] || sed 's/^/     /' "$tmp/get.log" >&2
expect "the gitdir is bare" true "$(git -C "$repo" rev-parse --is-bare-repository 2>/dev/null)"
expect "every remote branch is a remote-tracking ref" "origin/feat origin/main" \
    "$(git -C "$repo" for-each-ref --format='%(refname:short)' refs/remotes | sort | tr '\n' ' ' | sed 's/ $//')"
expect "the default branch is checked out beside the gitdir" main \
    "$(git -C "$repo/main" branch --show-current 2>/dev/null)"
expect "the default branch tracks origin" origin/main \
    "$(git -C "$repo/main" rev-parse --abbrev-ref '@{u}' 2>/dev/null)"
git -C "$tmp/up" -c user.name=t -c user.email=t@t commit -q --allow-empty -m two
git -C "$tmp/up" push -q "$tmp/fake/o/r" main
expect "a later pull fast-forwards" 2 \
    "$(env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$tmp/fake/.insteadOf" \
        GIT_CONFIG_VALUE_0=https://github.com/ git -C "$repo/main" pull -q --ff-only >/dev/null 2>&1
       git -C "$repo/main" rev-list --count HEAD)"
expect "the clone holds only the gitdir and the default worktree" ".git main" \
    "$(ls -A "$repo" | tr '\n' ' ' | sed 's/ $//')"

get o/r >"$tmp/again.log" 2>&1
rc=$?
expect "a second git get refuses the existing clone" yes "$([ "$rc" -ne 0 ] && echo yes || echo no)"
expect "the refusal leaves the checkout alone" main "$(git -C "$repo/main" branch --show-current)"

get >"$tmp/noarg.log" 2>&1
rc=$?
expect "git get with no repository fails" yes "$([ "$rc" -ne 0 ] && echo yes || echo no)"
expect "the failure names the usage" yes \
    "$(grep -q 'usage: git get owner/repo' "$tmp/noarg.log" && echo yes || echo no)"
expect "a failed git get creates nothing" "o" "$(ls "$repos/github.com")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
