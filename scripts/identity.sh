#!/bin/sh
# Identity hooks for the `identity` environment (see mise.identity.toml).
#   identity.sh check <name> <email> <key> <owner> <root> <work_owners> <flat> <work_email> <work_key>
#   identity.sh signers <email> <key> <work_email> <work_key>
set -eu

die() { printf 'identity: %s\n' "$*" >&2; exit 1; }

# Values render verbatim inside git-config double quotes, so anything git
# would treat as syntax there is refused: control characters (a newline would
# start a new config line), the double quote, and the backslash.
check_value() {
    case $2 in
        *[[:cntrl:]]*) die "$1 contains a control character; fix it with: mise vars $1=..." ;;
        *'"'*|*'\'*) die "$1 contains a double quote or backslash; fix it with: mise vars $1=..." ;;
    esac
}

expand_home() {
    # shellcheck disable=SC2088 # matching a literal ~/ that the vars store
    case $1 in
        '~/'*) printf '%s/%s' "$HOME" "${1#\~/}" ;;
        *) printf '%s' "$1" ;;
    esac
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
    check)
        [ $# -eq 9 ] || die "check takes 9 values, got $#"
        for name in git_name git_email git_signing_key personal_owner repos_root \
                work_owners work_flat_root work_email work_signing_key; do
            check_value "$name" "$1"
            eval "v_$name=\$1"
            shift
        done
        # shellcheck disable=SC2154 # assigned through eval above
        if { [ -n "$v_work_owners" ] || [ -n "$v_work_flat_root" ]; } && [ -z "$v_work_email" ]; then
            die "work_owners or work_flat_root is set, so work_email is required: mise vars work_email=..."
        fi
        ;;
    signers)
        [ $# -eq 4 ] || die "signers takes 4 values, got $#"
        email=$1 key=$2 work_email=${3:-$1} work_key=${4:-$2}
        dir=${XDG_CONFIG_HOME:-$HOME/.config}/ssh
        # ssh writes known_hosts beside the config, so the directory must exist
        # before the first connection.
        mkdir -p "$dir" && chmod 700 "$dir"
        out=""
        for pair in "$email $key" "$work_email $work_key"; do
            path=$(expand_home "${pair#* }")
            [ -r "$path" ] || continue
            line="${pair%% *} namespaces=\"git\" $(cat "$path")"
            case $out in *"$line"*) ;; *) out="$out$line
" ;; esac
        done
        # Never clobber a populated file when the keys are not on this machine
        # yet; create an empty one once so git has a file to read.
        if [ -n "$out" ]; then
            printf '%s' "$out" >"$dir/allowed_signers.tmp" && mv "$dir/allowed_signers.tmp" "$dir/allowed_signers"
        elif [ ! -e "$dir/allowed_signers" ]; then
            : >"$dir/allowed_signers"
        fi
        ;;
    *) die "usage: identity.sh check|signers ..." ;;
esac
