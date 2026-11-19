#!/bin/sh
# Create ~/.dotfiles (DOTFILES_LINK) as a symlink to the clean-bare main
# worktree (DOTFILES_CHECKOUT). Never replaces anything: what it refuses to
# touch exits 1; without the worktree it is a no-op.
set -eu

link=${DOTFILES_LINK:-$HOME/.dotfiles}
checkout=${DOTFILES_CHECKOUT:-/srv/git/github.com/smores56/dotfiles/main}

log() { printf 'dotfiles-layout: %s\n' "$*" >&2; }

[ -e "$checkout/.git" ] || { log "no checkout at $checkout; nothing to link"; exit 0; }

if [ -L "$link" ]; then
    target=$(readlink -f "$link" 2>/dev/null || printf '%s' "$link")
    want=$(readlink -f "$checkout" 2>/dev/null || printf '%s' "$checkout")
    [ "$target" = "$want" ] && exit 0
    log "$link points at $target, expected $checkout; leaving it alone"
    log "  ln -sfn $checkout $link"
    exit 1
fi

if [ -e "$link" ]; then
    log "$link exists and is not a symlink; leaving it alone"
    log "  mv $link $link.old && ln -s $checkout $link"
    exit 1
fi

parent=$(dirname "$link")
if ! mkdir -p "$parent" 2>/dev/null; then
    log "$parent is missing and not creatable by $(id -un)"
    exit 1
fi
if [ ! -w "$parent" ]; then
    log "$parent is not writable by $(id -un)"
    exit 1
fi

ln -s "$checkout" "$link"
log "linked $link -> $checkout"
