#!/bin/sh
# Clone a repository into ghq's clean-bare layout and check its default branch
# out as a worktree beside the gitdir, so one command yields a ready checkout.
set -eu

usage() {
    printf 'usage: %s <repository>\n' "${0##*/}" >&2
    printf 'repository: <owner>/<repo>, <host>/<owner>/<repo>, or a git URL\n' >&2
    exit 2
}

die() {
    printf 'clone-checkout: %s\n' "$*" >&2
    exit 1
}

usage_error() {
    printf 'clone-checkout: %s\n' "$*" >&2
    usage
}

# ghq lays a clone out as <root>/<host>/<path>, where shorthand specs mean
# GitHub and URL paths drop their .git suffix. Mirroring that rule is what lets
# the existing-path check below run before ghq turns its no-op into a lie.
destination() {
    case $1 in
        *://*)
            rest=${1#*://}
            rest=${rest#*@}
            host=${rest%%/*}
            path=${rest#*/}
            ;;
        *@*:*)
            rest=${1#*@}
            host=${rest%%:*}
            path=${rest#*:}
            ;;
        */*/*)
            host=${1%%/*}
            path=${1#*/}
            ;;
        */*)
            host=github.com
            path=$1
            ;;
        *)
            return 1
            ;;
    esac
    path=${path%/}
    path=${path%.git}
    [ -n "$host" ] && [ -n "$path" ] || return 1
    printf '%s/%s\n' "$host" "$path"
}

[ $# -eq 1 ] || usage
[ -n "$1" ] || usage

root=$(ghq root) || die "ghq root failed"
rel=$(destination "$1") \
    || usage_error "cannot place '$1'; expected <owner>/<repo>, <host>/<owner>/<repo>, or a git URL"
repo=$root/$rel
worktree=

if [ -d "$repo" ]; then
    # ghq is a no-op on an existing path, so a legacy full clone would sail
    # through and the worktree would land in the wrong shape. Refuse it here.
    if [ "$(git -C "$repo" rev-parse --is-bare-repository 2>/dev/null)" != true ]; then
        die "$repo is not a clean-bare checkout; remove it and re-run"
    fi
else
    ghq get --clean-bare "$1" >/dev/null || die "ghq get failed for '$1'"
    if [ ! -d "$repo/.git" ] \
            || [ "$(git -C "$repo" rev-parse --is-bare-repository 2>/dev/null)" != true ]; then
        die "ghq did not leave a clean-bare clone at $repo"
    fi
fi

branch=$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null) \
    || die "cannot read the default branch of $repo"
worktree=$repo/$branch

if [ -e "$worktree" ]; then
    die "$worktree already exists; cd there, or inspect: git -C $repo worktree list"
fi

git -C "$repo" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git -C "$repo" worktree add "$worktree" "$branch" >/dev/null \
    || die "could not check out $branch into $worktree"
git -C "$worktree" fetch origin || die "fetch of origin failed in $worktree"
git -C "$worktree" branch --set-upstream-to="origin/$branch" >/dev/null \
    || die "could not set $branch to track origin/$branch"

printf '%s\n' "$worktree"
