#!/bin/sh
# Maintain ~/.dotfiles as a symlink to the dotfiles default worktree.
#
# The checkout is a git worktree of the clean-bare repository under the ghq
# root; mise keeps its fixed ~/.dotfiles. bootstrap.sh creates the link once,
# and every bootstrap re-asserts it because a moved root would otherwise break
# every mise command. A machine without the worktree (the work laptop, which
# keeps a real clone) is a no-op.
#
#   DOTFILES_LINK      link to maintain (default ~/.dotfiles)
#   DOTFILES_CHECKOUT  worktree it points at
#                      (default /srv/git/github.com/smores56/dotfiles/main)
set -eu

link=${DOTFILES_LINK:-$HOME/.dotfiles}
checkout=${DOTFILES_CHECKOUT:-/srv/git/github.com/smores56/dotfiles/main}

log() { printf 'dotfiles-layout: %s\n' "$*"; }

[ -e "$checkout/.git" ] || { log "no checkout at $checkout; nothing to link"; exit 0; }

if [ -L "$link" ]; then
    target=$(readlink -f "$link" 2>/dev/null || printf '%s' "$link")
    want=$(readlink -f "$checkout" 2>/dev/null || printf '%s' "$checkout")
    [ "$target" = "$want" ] && exit 0
    log "$link points at $target, expected $checkout; leaving it alone"
    log "  ln -sfn $checkout $link"
    exit 0
fi

if [ -e "$link" ]; then
    log "$link exists and is not a symlink; leaving it alone"
    log "  mv $link $link.old && ln -s $checkout $link"
    exit 0
fi

parent=$(dirname "$link")
if [ ! -d "$parent" ]; then
    if ! mkdir -p "$parent" 2>/dev/null; then
        log "$parent is missing and not creatable by $(id -un)"
        exit 0
    fi
fi
if [ ! -w "$parent" ]; then
    log "$parent is not writable by $(id -un)"
    exit 0
fi

ln -s "$checkout" "$link"
log "linked $link -> $checkout"
