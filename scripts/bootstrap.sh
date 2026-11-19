#!/bin/sh
# bootstrap.sh: bring a fresh personal Linux machine to a dotfiles checkout.
#
# Served as https://bootstrap.sammohr.dev (a Cloudflare redirect to this file
# on main), so it must run without a checkout, without mise, and without any
# repo config:
#
#   1. create the ghq root (the one sudo prompt)
#   2. install mise, the same official installer install-mise.sh uses
#   3. clone the dotfiles with ghq's clean-bare layout
#   4. add the default worktree and point ~/.dotfiles at it
#   5. hand off to the checkout's install-mise.sh
#
# The work laptop is macOS and keeps a normal clone, so it is refused here.
#
# Overrides exist for the behavioural test; the defaults are the real ones.
set -eu

REMOTE=${BOOTSTRAP_REMOTE:-https://github.com/smores56/dotfiles.git}
ROOT=${BOOTSTRAP_ROOT:-/srv/git}
CHECKOUT=${BOOTSTRAP_CHECKOUT:-$HOME/.dotfiles}
GHQ_VERSION=${GHQ_VERSION:-1.12.0}
MISE=$HOME/.local/bin/mise

die() { printf 'bootstrap: %s\n' "$*" >&2; exit 1; }
log() { printf 'bootstrap: %s\n' "$*"; }

[ "$(uname -s)" = Darwin ] && die "macOS keeps a normal clone; run ~/.dotfiles/scripts/install-mise.sh instead"

case $REMOTE in
    https://*) path=${REMOTE#https://} ;;
    *) die "expected an https remote, got: $REMOTE" ;;
esac
path=${path%.git}
case $path in
    */*/*) ;;
    *) die "expected host/owner/repo in the remote, got: $REMOTE" ;;
esac
host=${path%%/*}
case $host in
    *@*|*:*) die "credentials in the remote are not supported: $REMOTE" ;;
esac
rest=${path#*/}
owner=${rest%%/*}
name=${rest#*/}
for part in "$host" "$owner" "$name"; do
    case $part in
        ''|.|..|-*) die "invalid path component in the remote: $part" ;;
    esac
done
repo=$ROOT/$path
checkout_target=$repo/main

# A real directory at the checkout is a pre-clean-bare machine: converting it
# moves the running checkout, so it is a human step (docs/manual-steps.md).
if [ -e "$CHECKOUT" ] || [ -L "$CHECKOUT" ]; then
    [ -L "$CHECKOUT" ] || die "$CHECKOUT is a real directory; see the migration note in docs/manual-steps.md"
    # A broken link whose target is the expected worktree is repaired below,
    # so compare the raw target as well as the resolved one: readlink -f
    # fails for both when the root or the worktree is missing.
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

if [ ! -x "$MISE" ]; then
    log "installing mise"
    curl -fsSL --proto '=https' --tlsv1.2 https://mise.run \
        | MISE_VERSION='' MISE_MINIMUM_RELEASE_AGE=0s MISE_INSTALL_HELP=0 sh \
        || die "the official mise installer failed"
    [ -x "$MISE" ] || die "the official installer did not write $MISE"
fi

# Always the pinned ghq through mise: a `ghq` on PATH may be a stale shim or a
# binary another writer controls, and this clone's scripts run below.
log "cloning $REMOTE"
GHQ_ROOT="$ROOT" MISE_LOCKED=0 "$MISE" exec "ghq@$GHQ_VERSION" -- ghq \
    get --clean-bare "$REMOTE" || die "ghq get failed"
[ -d "$repo/.git" ] || die "ghq did not create $repo/.git"

git -C "$repo" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
if [ ! -e "$repo/main" ]; then
    git -C "$repo" worktree add "$repo/main" main || die "could not add the main worktree"
fi
git -C "$repo/main" fetch origin || die "could not fetch origin"
git -C "$repo/main" branch --set-upstream-to=origin/main >/dev/null \
    || die "could not set main's upstream"

DOTFILES_LINK=$CHECKOUT DOTFILES_CHECKOUT=$repo/main \
    sh "$repo/main/scripts/link-dotfiles-checkout.sh" \
    || die "could not link $CHECKOUT"

[ -x "$CHECKOUT/scripts/install-mise.sh" ] \
    || die "$CHECKOUT is not the linked worktree; see the link script output above"

log "running the checkout's installer"
exec "$CHECKOUT/scripts/install-mise.sh"
