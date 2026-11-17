#!/bin/sh
# Identity hooks for the `identity` and `work` environments.
# Every value is fixed: personal sam@sammohr.dev, work smohr@blitzy.com.
#   identity.sh signers        personal machine: personal and work keys
#   identity.sh work-signers   work machine: the checked-in 1Password key
set -eu

die() { printf 'identity: %s\n' "$*" >&2; exit 1; }

expand_home() {
    # shellcheck disable=SC2088 # matching a literal ~/ that the config stores
    case $1 in
        '~/'*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
        *) printf '%s' "$1" ;;
    esac
}

# ~/.gitconfig names ~/.config/ssh/allowed_signers literally, so this path
# must not follow XDG_CONFIG_HOME. ssh also writes known_hosts beside it, so
# the directory must exist before the first connection.
dir=$HOME/.config/ssh

write_signers() {
    mkdir -p "$dir" && chmod 700 "$dir"
    : >"$dir/allowed_signers.tmp"
    for pair in "$@"; do
        email=${pair%% *}
        key=${pair#* }
        path=$(expand_home "$key")
        if [ ! -f "$path" ] || [ ! -r "$path" ]; then
            printf 'identity: %s is not a readable key file; allowed_signers skips it\n' "$key" >&2
            continue
        fi
        # A .pub file holds one key; anything after its first line is not part of it.
        IFS= read -r key_line <"$path" || [ -n "$key_line" ] || continue
        printf '%s namespaces="git" %s\n' "$email" "$key_line" >>"$dir/allowed_signers.tmp"
    done
    mv "$dir/allowed_signers.tmp" "$dir/allowed_signers"
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
    signers)
        [ $# -eq 0 ] || die "signers takes no arguments"
        write_signers \
            "sam@sammohr.dev ~/.ssh/id_ed25519.pub" \
            "smohr@blitzy.com ~/.ssh/id_work.pub"
        ;;
    work-signers)
        [ $# -eq 0 ] || die "work-signers takes no arguments"
        write_signers "smohr@blitzy.com ~/.config/git/work-signing.pub"
        ;;
    *) die "usage: identity.sh signers|work-signers" ;;
esac
