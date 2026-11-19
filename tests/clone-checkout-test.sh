#!/usr/bin/env bash
# Behavioral tests for scripts/clone-checkout.sh, with a fake ghq so the suite
# needs no network: the fake reproduces ghq's "no-op on an existing path".
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
expect() {  # expect <desc> <want> <got>
    if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$2', got '$3')"; fi
}
contains() {  # contains <desc> <needle> <haystack>
    case $3 in
        *"$2"*) ok "$1" ;;
        *) no "$1 (want '$2' in '$3')" ;;
    esac
}

seed_bare() {  # seed_bare <dir> — bare repo with one main commit
    git init -q --bare "$1"
    tree=$(git -C "$1" mktree </dev/null) || return 1
    commit=$(git -C "$1" -c user.name=test -c user.email=test@example.com \
        commit-tree "$tree" -m init) || return 1
    git -C "$1" update-ref refs/heads/main "$commit" || return 1
    git -C "$1" symbolic-ref HEAD refs/heads/main
}

ghq_root=$tmp/ghq
mkdir -p "$ghq_root"
seed_bare "$tmp/origin.git" || exit 1

bin=$tmp/bin
mkdir -p "$bin"
cat >"$bin/ghq" <<'FAKE'
#!/bin/sh
case ${1:-} in
root)
    printf '%s\n' "${FAKE_GHQ_ROOT:?}"
    ;;
get)
    [ "${FAKE_GHQ_FAIL:-}" = 1 ] && exit 1
    # ghq leaves an existing path alone, clone or not.
    [ -d "$FAKE_GHQ_TARGET/.git" ] && exit 0
    mkdir -p "$FAKE_GHQ_TARGET"
    seed_bare() {
        git init -q --bare "$1"
        tree=$(git -C "$1" mktree </dev/null) || return 1
        commit=$(git -C "$1" -c user.name=test -c user.email=test@example.com \
            commit-tree "$tree" -m init) || return 1
        git -C "$1" update-ref refs/heads/main "$commit" || return 1
        git -C "$1" symbolic-ref HEAD refs/heads/main
    }
    seed_bare "$FAKE_GHQ_TARGET/.git" || exit 1
    git -C "$FAKE_GHQ_TARGET/.git" remote add origin "${FAKE_ORIGIN:?}"
    ;;
*)
    exit 2
    ;;
esac
FAKE
chmod +x "$bin/ghq"

run() {  # run <spec> — FAKE_GHQ_TARGET must be set by the caller
    env -i HOME="$tmp/home" PATH="$bin:$PATH" \
        FAKE_GHQ_ROOT="$ghq_root" FAKE_GHQ_TARGET="${FAKE_GHQ_TARGET:-}" \
        FAKE_GHQ_FAIL="${FAKE_GHQ_FAIL:-}" FAKE_ORIGIN="$tmp/origin.git" \
        sh "$root/scripts/clone-checkout.sh" "$@"
}

out=$(run 2>"$tmp/err.log")
status=$?
expect "no arguments exits 2" 2 "$status"
contains "no arguments prints usage" usage "$(cat "$tmp/err.log")"

# --- a fresh clone gets the default branch as a worktree

FAKE_GHQ_TARGET=$ghq_root/github.com/acme/widget
out=$(run acme/widget 2>"$tmp/err.log")
status=$?
expect "acme/widget clones" 0 "$status"
expect "the worktree path is printed" "$FAKE_GHQ_TARGET/main" "$out"
expect "the gitdir is bare" true \
    "$(git -C "$FAKE_GHQ_TARGET" rev-parse --is-bare-repository 2>/dev/null)"
expect "the default branch is checked out" main \
    "$(git -C "$FAKE_GHQ_TARGET/main" symbolic-ref --short HEAD 2>/dev/null)"
expect "the branch tracks origin/main" origin/main \
    "$(git -C "$FAKE_GHQ_TARGET/main" rev-parse --abbrev-ref '@{u}' 2>/dev/null)"
expect "the fetch refspec covers every branch" '+refs/heads/*:refs/remotes/origin/*' \
    "$(git -C "$FAKE_GHQ_TARGET" config remote.origin.fetch)"

out=$(run acme/widget 2>"$tmp/err.log")
status=$?
expect "re-running on a set-up checkout fails" 1 "$status"
contains "re-running explains the checkout exists" "already exists" "$(cat "$tmp/err.log")"

# --- destination parsing mirrors ghq

FAKE_GHQ_TARGET=$ghq_root/github.com/acme/gadget
out=$(run https://github.com/acme/gadget.git 2>"$tmp/err.log")
expect "an https URL clones" 0 "$?"
expect "an https URL keeps host and path" "$FAKE_GHQ_TARGET/main" "$out"

FAKE_GHQ_TARGET=$ghq_root/github.com/acme/sprocket
out=$(run git@github.com:acme/sprocket.git 2>"$tmp/err.log")
expect "an scp-style URL clones" 0 "$?"
expect "an scp-style URL keeps host and path" "$FAKE_GHQ_TARGET/main" "$out"

FAKE_GHQ_TARGET=$ghq_root/codeberg.org/acme/cog
out=$(run codeberg.org/acme/cog 2>"$tmp/err.log")
expect "a host-qualified spec clones" 0 "$?"
expect "a host-qualified spec keeps the host" "$FAKE_GHQ_TARGET/main" "$out"

FAKE_GHQ_TARGET=$ghq_root/github.com/acme/bad
out=$(run justaname 2>"$tmp/err.log")
status=$?
expect "a bare name exits 2" 2 "$status"
contains "a bare name explains the accepted forms" "expected" "$(cat "$tmp/err.log")"

# --- an old normal clone is refused, never mistaken for a clean-bare one

legacy=$ghq_root/github.com/acme/legacy
mkdir -p "$legacy"
git init -q "$legacy"
git -C "$legacy" -c user.name=test -c user.email=test@example.com \
    commit --allow-empty -q -m init
FAKE_GHQ_TARGET=$legacy
out=$(run acme/legacy 2>"$tmp/err.log")
status=$?
expect "a normal clone is refused" 1 "$status"
contains "a normal clone explains the removal" "remove it" "$(cat "$tmp/err.log")"

# --- a clean-bare clone left without a worktree is completed, not re-cloned

resume=$ghq_root/github.com/acme/resume
mkdir -p "$resume"
seed_bare "$resume/.git"
git -C "$resume/.git" remote add origin "$tmp/origin.git"
FAKE_GHQ_TARGET=$resume
out=$(run acme/resume 2>"$tmp/err.log")
expect "an unfinished clean-bare clone gets its worktree" "$resume/main" "$out"

# --- ghq failures surface

FAKE_GHQ_TARGET=$ghq_root/github.com/acme/broken
out=$(FAKE_GHQ_FAIL=1 run acme/broken 2>"$tmp/err.log")
status=$?
expect "a ghq failure fails" 1 "$status"
contains "a ghq failure names the spec" "acme/broken" "$(cat "$tmp/err.log")"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
