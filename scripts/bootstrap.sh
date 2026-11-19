#!/bin/sh
# Bring a fresh personal Linux machine to a clean-bare dotfiles checkout, then
# hand off to its install-mise.sh. Served as https://bootstrap.sammohr.dev, so it
# runs without a checkout or mise. The BOOTSTRAP_* overrides exist for the test.
set -eu

REMOTE=${BOOTSTRAP_REMOTE:-https://github.com/smores56/dotfiles.git}
ROOT=${BOOTSTRAP_ROOT:-/srv/git}
CHECKOUT=${BOOTSTRAP_CHECKOUT:-$HOME/.dotfiles}

die() { printf 'bootstrap: %s\n' "$*" >&2; exit 1; }
log() { printf 'bootstrap: %s\n' "$*"; }

[ "$(uname -s)" = Darwin ] && die "macOS keeps a normal clone; run ~/.dotfiles/scripts/install-mise.sh instead"

case $REMOTE in
    https://*) path=${REMOTE#https://} ;;
    *) die "expected an https remote, got: $REMOTE" ;;
esac
path=${path%.git}
old_ifs=$IFS
IFS=/
# shellcheck disable=SC2086 # splitting on / is the point
set -- $path
IFS=$old_ifs
[ $# -eq 3 ] || die "expected host/owner/repo in the remote, got: $REMOTE"
host=$1
owner=$2
name=$3
for part in "$host" "$owner" "$name"; do
    case $part in
        ''|.|..|*..*|-*) die "invalid path component in the remote: $part" ;;
    esac
done
case $host in
    *@*|*:*) die "credentials in the remote are not supported: $REMOTE" ;;
esac
repo=$ROOT/$host/$owner/$name
checkout_target=$repo/main

if [ -e "$CHECKOUT" ] || [ -L "$CHECKOUT" ]; then
    [ -L "$CHECKOUT" ] || die "$CHECKOUT is a real directory; move it aside and re-run"
    # readlink -f fails while the worktree is missing, so a broken link to the
    # expected target also passes; the link script repairs it below.
    raw=$(readlink "$CHECKOUT")
    resolved=$(readlink -f "$CHECKOUT" 2>/dev/null || printf '%s' "$CHECKOUT")
    want=$(readlink -f "$checkout_target" 2>/dev/null || printf '%s' "$checkout_target")
    [ "$raw" = "$checkout_target" ] || [ "$resolved" = "$want" ] \
        || die "$CHECKOUT points at $raw, expected $checkout_target; resolve it by hand"
fi

if [ ! -d "$ROOT" ]; then
    command -v sudo >/dev/null 2>&1 || die "sudo is required to create $ROOT"
    sudo install -d -o "$(id -un)" -g "$(id -gn)" "$ROOT" || die "could not create $ROOT"
elif [ ! -w "$ROOT" ]; then
    command -v sudo >/dev/null 2>&1 || die "$ROOT is not writable and sudo is missing"
    sudo chown "$(id -un):$(id -gn)" "$ROOT" || die "could not take ownership of $ROOT"
fi

# The refspec at clone time fills origin/* in the same pass, so main can track it.
refspec='+refs/heads/*:refs/remotes/origin/*'
if [ ! -e "$repo/.git" ]; then
    log "cloning $REMOTE"
    git clone --bare -c remote.origin.fetch="$refspec" "$REMOTE" "$repo/.git" \
        || die "could not clone $REMOTE"
fi
git -C "$repo" rev-parse --is-bare-repository 2>/dev/null | grep -qx true \
    || die "$repo is not a clean-bare clone; remove the old checkout and re-run"

git -C "$repo" config remote.origin.fetch "$refspec"
git -C "$repo" fetch origin || die "could not fetch origin"
if [ ! -e "$repo/main" ]; then
    git -C "$repo" worktree add -B main "$repo/main" origin/main >/dev/null \
        || die "could not add the main worktree"
fi
git -C "$repo/main" branch --set-upstream-to=origin/main >/dev/null \
    || die "could not set main's upstream"

DOTFILES_LINK=$CHECKOUT DOTFILES_CHECKOUT=$repo/main \
    sh "$repo/main/scripts/link-dotfiles-checkout.sh" \
    || die "could not link $CHECKOUT"

[ -x "$CHECKOUT/scripts/install-mise.sh" ] \
    || die "$CHECKOUT is not the linked worktree; see the link script output above"

log "running the checkout's installer"
exec "$CHECKOUT/scripts/install-mise.sh"
