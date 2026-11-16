#!/bin/sh
# handoff.sh: move one piece of smoreswork from home-manager to this
# repository, or move it back.
#
# usage: handoff.sh [--dry-run] apply|rollback <piece>
#   pieces: zsh helix zellij yazi lazygit television gh aerospace
#
# apply: first add the piece to `user.dotfilesOwns` for sam@smoreswork in
# nix-config. Then this records the active home-manager generation, switches
# home-manager (which removes the piece's links), refuses to continue if any
# target is still home-manager's, and applies the piece's dotfiles at once, so
# no shell starts with neither config in place.
# rollback: unapplies the piece's dotfiles first (home-manager refuses to
# overwrite files it does not own), then re-activates the recorded generation.
# Remove the piece from `user.dotfilesOwns` afterwards, or the next switch
# drops it again.
# The ~/ targets are mise entry keys, passed through unexpanded on purpose.
# shellcheck disable=SC2088
set -eu

DOTFILES=${DOTFILES:-$HOME/repos/github.com/smores56/dotfiles}
NIX_CONFIG=${NIX_CONFIG:-$HOME/repos/github.com/smores56/nix-config}
HM_TARGET=${HM_TARGET:-sam@smoreswork}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-handoff

die() { printf 'handoff: %s\n' "$*" >&2; exit 1; }
say() { printf 'handoff: %s\n' "$*"; }

dry_run=false
[ "${1:-}" = --dry-run ] && { dry_run=true; shift; }
[ $# -eq 2 ] || die "usage: handoff.sh [--dry-run] apply|rollback <piece>"
action=$1 piece=$2

# The dotfile targets each piece owns, as declared in mise.toml and its envs.
case $piece in
    zsh) targets='~/.zshenv ~/.config/zsh ~/.config/zsh/env.d/work.zsh ~/.config/zsh/conf.d/90-work.zsh' ;;
    helix|zellij|yazi|lazygit|television|gh) targets="~/.config/$piece" ;;
    aerospace) targets='~/.aerospace.toml' ;;
    *) die "unknown piece: $piece" ;;
esac

run() {
    if $dry_run; then
        printf 'would run:'
        printf ' %s' "$@"
        printf '\n'
    else
        "$@"
    fi
}

expand() { case $1 in '~/'*) printf '%s/%s' "$HOME" "${1#\~/}" ;; *) printf '%s' "$1" ;; esac; }

# True while any target (or a file inside a target directory) is a link into
# the Nix store, that is, still written by home-manager.
hm_owns() {
    for t in $targets; do
        p=$(expand "$t")
        if [ -L "$p" ]; then
            case $(readlink "$p") in /nix/store/*) return 0 ;; esac
        elif [ -d "$p" ]; then
            for f in "$p"/* "$p"/.[!.]*; do
                [ -L "$f" ] || continue
                case $(readlink "$f") in /nix/store/*) return 0 ;; esac
            done
        fi
    done
    return 1
}

dot() {
    # shellcheck disable=SC2086 # targets are plain words
    run mise -C "$DOTFILES" dot "$@" $targets
}

case $action in
    apply)
        mkdir -p "$STATE"
        current=$(readlink "$HOME/.local/state/nix/profiles/home-manager" 2>/dev/null || true)
        [ -n "$current" ] || die "no active home-manager generation found"
        $dry_run || printf '%s\n' "$current" >"$STATE/$piece.before"
        say "home-manager generation before the handoff: $current"
        run home-manager switch --flake "$NIX_CONFIG#$HM_TARGET"
        if ! $dry_run && hm_owns; then
            die "home-manager still writes the $piece files; add \"$piece\" to user.dotfilesOwns in nix-config and retry"
        fi
        # home-manager's completion dumps are named for its own generations.
        if [ "$piece" = zsh ]; then
            for f in "$HOME"/.config/zsh/.zcompdump*; do
                [ -e "$f" ] && run rm -f "$f"
            done
        fi
        dot apply
        say "$piece now comes from $DOTFILES"
        ;;
    rollback)
        [ -f "$STATE/$piece.before" ] || die "no recorded generation for $piece; nothing to roll back to"
        before=$(cat "$STATE/$piece.before")
        dot unapply
        run "$HOME/.local/state/nix/profiles/$before/activate"
        $dry_run || rm -f "$STATE/$piece.before"
        say "$piece is home-manager's again (generation $before); remove it from user.dotfilesOwns"
        ;;
    *) die "unknown action: $action (apply or rollback)" ;;
esac
