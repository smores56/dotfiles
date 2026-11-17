#!/bin/sh
# handoff.sh: move one piece of smoreswork from home-manager to this
# repository, or move it back.
#
# usage: handoff.sh [--dry-run] apply <piece>
#        handoff.sh [--dry-run] rollback [--previous] <piece>
#   pieces: zsh helix zellij yazi lazygit television gh aerospace
#
# apply: first add the piece to `user.dotfilesOwns` for sam@smoreswork in
# nix-config. This records the active home-manager generation (once), switches
# home-manager so it drops the piece's links, refuses while any of them is
# still home-manager's, then applies the piece's dotfiles straight away and
# checks every target landed.
#
# rollback: first remove the piece from `user.dotfilesOwns`. This unapplies the
# piece's dotfiles (home-manager refuses to overwrite files it does not own),
# switches home-manager so it writes them again, and checks it did.
# rollback --previous is the emergency path when nix-config cannot be edited:
# it re-activates the generation recorded before the handoff, and only for the
# most recent handoff, since an older generation would also undo later ones.
#
# The ~/ targets are mise entry keys, passed through unexpanded on purpose.
# shellcheck disable=SC2088
set -eu

DOTFILES=${DOTFILES:-$HOME/.dotfiles}
# Not NIX_CONFIG: Nix reads that variable as nix.conf contents.
NIX_CONFIG_DIR=${NIX_CONFIG_DIR:-/srv/git/github.com/smores56/nix-config}
HM_TARGET=${HM_TARGET:-sam@smoreswork}
# The environment set smoreswork applies; passed explicitly so a missing saved
# set can never drop the work hooks silently.
HANDOFF_ENV=${HANDOFF_ENV:-desktop,work}
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-handoff
PROFILES=$HOME/.local/state/nix/profiles

die() { printf 'handoff: %s\n' "$*" >&2; exit 1; }
say() { printf 'handoff: %s\n' "$*"; }

dry_run=false
previous=false
[ "${1:-}" = --dry-run ] && { dry_run=true; shift; }
action=${1:-}
[ $# -gt 0 ] && shift
[ "$action" = rollback ] && [ "${1:-}" = --previous ] && { previous=true; shift; }
[ $# -eq 1 ] || die "usage: handoff.sh [--dry-run] apply <piece> | rollback [--previous] <piece>"
piece=$1

# The dotfile targets each piece owns, as declared in mise.toml and its envs.
case $piece in
    zsh) targets='~/.zshenv ~/.config/zsh ~/.config/zsh/env.d/work.zsh ~/.config/zsh/conf.d/90-work.zsh'
        checks='~/.zshenv
~/.config/zsh/.zshrc
~/.config/zsh/env.d/work.zsh
~/.config/zsh/conf.d/90-work.zsh' ;;
    lazygit) targets='~/.config/lazygit'
        if [ "$(uname -s)" = Darwin ]; then
            checks='~/Library/Application Support/lazygit/config.yml'
        else
            checks='~/.config/lazygit/config.yml'
        fi ;;
    helix|zellij|yazi|television|gh) targets="~/.config/$piece" checks=$targets ;;
    aerospace) targets='~/.aerospace.toml' checks=$targets ;;
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

# True while any target, or any link at any depth inside a target directory,
# points into the Nix store, that is, is still written by home-manager.
hm_owns() {
    for t in $targets; do
        p=$(expand "$t")
        [ "$piece" = lazygit ] && [ "$(uname -s)" = Darwin ] && p="$HOME/Library/Application Support/lazygit"
        [ -e "$p" ] || [ -L "$p" ] || continue
        if find "$p" -type l -exec readlink {} \; 2>/dev/null | grep -q '^/nix/store/'; then
            return 0
        fi
    done
    return 1
}

# Every check path exists after an apply; mise reports a target it cannot
# resolve as a warning and still exits 0.
verify_applied() {
    missing=""
    old_ifs=$IFS
    IFS='
'
    for t in $checks; do
        [ -e "$(expand "$t")" ] || missing="$missing $t"
    done
    IFS=$old_ifs
    [ -z "$missing" ] || die "the $piece dotfiles did not land:$missing"
}

dot() {
    # shellcheck disable=SC2086 # targets are plain words
    run mise -C "$DOTFILES" -E "$HANDOFF_ENV" dot "$@" $targets
}

switch() { run home-manager switch --flake "$NIX_CONFIG_DIR#$HM_TARGET"; }

# The login shell must not live in the Nix profile before zsh moves: if a
# later home-manager change dropped that binary, every new login would fail.
login_shell() {
    if [ "$(uname -s)" = Darwin ]; then
        dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | sed 's/^UserShell: //'
    else
        getent passwd "$(id -un)" | cut -d: -f7
    fi
}

case $action in
    apply)
        if [ "$piece" = zsh ] && [ -z "${HANDOFF_SKIP_SHELL_CHECK-}" ]; then
            case $(login_shell) in
                /nix/*|"$HOME"/.nix-profile/*)
                    die "the login shell is $(login_shell); switch it first: mise -C $DOTFILES -E $HANDOFF_ENV bootstrap --only user" ;;
            esac
        fi
        current=$(readlink "$PROFILES/home-manager" 2>/dev/null || true)
        [ -n "$current" ] || die "no active home-manager generation found"
        # Recorded once: a retried apply must keep the generation from before
        # the first attempt, which is the one that still owns the piece.
        if [ ! -f "$STATE/$piece.before" ]; then
            say "home-manager generation before the handoff: $current"
            if ! $dry_run; then
                mkdir -p "$STATE"
                printf '%s\n' "$current" >"$STATE/$piece.before"
                printf '%s\n' "$piece" >>"$STATE/order"
            fi
        fi
        switch
        if hm_owns; then
            $dry_run && { say "home-manager still writes the $piece files; a real run would stop here"; exit 0; }
            die "home-manager still writes the $piece files; add \"$piece\" to user.dotfilesOwns in nix-config and retry"
        fi
        # home-manager's completion dumps are named for its own generations.
        if [ "$piece" = zsh ]; then
            for f in "$HOME"/.config/zsh/.zcompdump*; do
                [ -e "$f" ] && run rm -f "$f"
            done
        fi
        dot apply
        $dry_run || verify_applied
        # zim had nothing to build before this repository's .zimrc arrived.
        # HANDOFF_SKIP_ZIM is for the tests, whose fixture has no plugin clones.
        if [ "$piece" = zsh ] && [ -z "${HANDOFF_SKIP_ZIM-}" ]; then
            run sh "$DOTFILES/scripts/zim-build.sh"
        fi
        say "$piece now comes from $DOTFILES"
        ;;
    rollback)
        if $previous; then
            [ -f "$STATE/$piece.before" ] || die "no recorded generation for $piece"
            last=$(tail -n 1 "$STATE/order" 2>/dev/null || true)
            [ "$last" = "$piece" ] || die "--previous only undoes the latest handoff ($last); its generation would also undo the later ones"
            before=$(cat "$STATE/$piece.before")
            [ -x "$PROFILES/$before/activate" ] || die "generation $before is gone (garbage-collected?); use a plain rollback"
            dot unapply
            run "$PROFILES/$before/activate"
        else
            dot unapply
            switch
            if ! $dry_run && ! hm_owns; then
                die "home-manager did not write the $piece files back; remove \"$piece\" from user.dotfilesOwns and run: home-manager switch --flake $NIX_CONFIG_DIR#$HM_TARGET"
            fi
        fi
        if ! $dry_run; then
            rm -f "$STATE/$piece.before"
            if [ -f "$STATE/order" ]; then
                grep -vx "$piece" "$STATE/order" >"$STATE/order.tmp" || true
                mv "$STATE/order.tmp" "$STATE/order"
            fi
        fi
        say "$piece is home-manager's again"
        ;;
    *) die "unknown action: $action (apply or rollback)" ;;
esac
