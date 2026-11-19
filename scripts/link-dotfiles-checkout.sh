#!/bin/sh
# Keep /srv/git/<host>/<owner>/<repo> pointing at the live checkout.
#
# The checkout stays where mise puts it (~/.dotfiles on every machine); the /srv
# path is the stable alias the agent instructions and `repos` use. install-mise.sh
# creates it once, but it is the one piece of that install a later move can drop,
# so bootstrap re-asserts it whenever the parent is writable. Nothing is created
# when it cannot be: a foreign-owned /srv/git needs the single sudo in
# install-mise.sh, not a bootstrap that half-succeeds.
#
#   DOTFILES_LINK       alias to maintain (default /srv/git/github.com/smores56/dotfiles)
#   DOTFILES_CHECKOUT   checkout it points at (default $HOME/.dotfiles)
set -eu

link=${DOTFILES_LINK:-/srv/git/github.com/smores56/dotfiles}
checkout=${DOTFILES_CHECKOUT:-$HOME/.dotfiles}

log() { printf 'dotfiles-layout: %s\n' "$*"; }

[ -d "$checkout/.git" ] || { log "no checkout at $checkout; nothing to link"; exit 0; }

if [ -L "$link" ]; then
    target=$(readlink -f "$link" 2>/dev/null || printf '%s' "$link")
    [ "$target" = "$(readlink -f "$checkout")" ] && exit 0
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
        log "  sudo install -d -o $(id -un) -g $(id -gn) /srv/git   # install-mise.sh does this"
        exit 0
    fi
fi
if [ ! -w "$parent" ]; then
    log "$parent is not writable by $(id -un); install-mise.sh takes ownership with one sudo"
    exit 0
fi

ln -s "$checkout" "$link"
log "linked $link -> $checkout"
