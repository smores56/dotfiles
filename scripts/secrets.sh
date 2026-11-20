#!/bin/sh
# Decrypt sops.yaml once (one passphrase prompt) into three mode-600 files: the
# Maki provider keys, the machine's GitHub token, and the smortress ssh key.
set -eu

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cipher=${DOTFILES_SECRETS:-$root/sops.yaml}
config=${XDG_CONFIG_HOME:-$HOME/.config}
secrets=$config/maki/secrets.env
token=$config/gh/token
ssh_key=$HOME/.ssh/id_smortress
key=$config/sops/keys.age
state=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/secrets.sha256

log() { printf 'secrets: %s\n' "$*" >&2; }

# An absent key in the cipher is not proof the credential should go: a checkout
# that is behind carries an older cipher than the one that delivered the file,
# and deleting on absence turns that into a silent outage. Removal is explicit.
prune=false
case ${1:-} in
    --prune) prune=true ;;
    '') ;;
    *) printf 'usage: %s [--prune]\n' "$0" >&2; exit 2 ;;
esac

[ -f "$cipher" ] || exit 0
keycmd=$HOME/.local/bin/sops-age-key
if [ -x "$keycmd" ]; then
    if ! reason=$("$keycmd" --check 2>&1); then
        log "no usable SOPS identity: ${reason:-unknown}"
        log "leaving the secrets alone"
        exit 0
    fi
elif [ ! -r "$key" ]; then
    log "no $key on this machine; leaving the secrets alone"
    exit 0
fi

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

# mise exports MISE_ENV only to what it runs, and not at all for an empty set,
# so unset is ambiguous: ask mise rather than let a hand run on a work machine
# fall through to the personal PAT.
if [ -z "${MISE_ENV+x}" ]; then
    # shellcheck disable=SC2016 # the inner shell expands it, under mise
    MISE_ENV=$(cd "$root" && MISE_EXEC_AUTO_INSTALL=false \
        mise exec -- sh -c 'printf %s "${MISE_ENV-}"') || {
        log "cannot read the environment set from mise; run: mise exec -- sh scripts/secrets.sh"
        exit 1
    }
fi

case ",${MISE_ENV-}," in
    *,work,*) pat_name=GITHUB_WORK_PAT ;;
    *) pat_name=GITHUB_PERSONAL_PAT ;;
esac

want=$(sha256_of "$cipher")
state_line=$(cat "$state" 2>/dev/null || true)
have=
token_marker=
ssh_key_marker=
if [ -n "$state_line" ]; then
    # <cipher sha> <token marker> <ssh key marker>; a missing marker forces a
    # decrypt, so a state from an older script still settles.
    read -r have token_marker ssh_key_marker _rest <<EOF
$state_line
EOF
fi
# --prune has work to do even when the ciphertext is unchanged, so it never
# takes the satisfied path.
if ! $prune && [ "$want" = "$have" ] && [ -s "$secrets" ]; then
    # A restored or copied file can lose its mode; repair it on every run.
    chmod 600 "$secrets"
    token_ok=no
    case $token_marker in
        "$pat_name:none") token_ok=yes ;;
        "$pat_name") [ -s "$token" ] && { chmod 600 "$token"; token_ok=yes; } ;;
    esac
    ssh_key_ok=no
    case $ssh_key_marker in
        yes) [ -s "$ssh_key" ] && { chmod 600 "$ssh_key"; ssh_key_ok=yes; } ;;
    esac
    if [ "$token_ok" = yes ] && [ "$ssh_key_ok" = yes ]; then
        exit 0
    fi
fi

if [ -x "$HOME/.local/bin/sops-age-key" ]; then
    : "${SOPS_AGE_KEY_CMD:=$HOME/.local/bin/sops-age-key}"
    export SOPS_AGE_KEY_CMD
fi

tmp=$(mktemp) || { log "cannot create a temporary file"; exit 1; }
trap 'rm -f "$tmp"' EXIT HUP INT TERM
sops --decrypt --output-type dotenv "$cipher" >"$tmp" \
    || { log "sops could not decrypt $cipher"; exit 1; }

value_of() {
    v=$(sed -n "s/^${1}=//p" "$tmp" | head -n 1 | tr -d '\r')
    case $v in
        \"*\") v=${v#\"}; v=${v%\"} ;;
        \'*\') v=${v#\'}; v=${v%\'} ;;
    esac
    printf '%s' "$v"
}

neuralwatt=$(value_of NEURALWATT_API_KEY)
tinyfish=$(value_of TINYFISH_API_KEY)
# sops writes a multi-line dotenv value on one double-quoted line with \n
# escapes; ssh needs the real newlines back.
ssh_key_value=$(printf '%b' "$(value_of SMORTRESS_SSH_KEY)")
pat=$(value_of "$pat_name")

if [ -z "$neuralwatt" ] || [ -z "$tinyfish" ] || [ -z "$ssh_key_value" ]; then
    log "$cipher needs NEURALWATT_API_KEY, TINYFISH_API_KEY and SMORTRESS_SSH_KEY; leaving the secrets alone"
    exit 1
fi

umask 077
write_private() {  # write_private <path> <line>...: atomic, mode 600
    f=$1
    shift
    mkdir -p "$(dirname "$f")"
    printf '%s\n' "$@" >"$f.tmp.$$"
    mv "$f.tmp.$$" "$f"
    chmod 600 "$f"
}

write_private "$secrets" "NEURALWATT_API_KEY=$neuralwatt" "TINYFISH_API_KEY=$tinyfish"
write_private "$ssh_key" "$ssh_key_value"
ssh_key_marker=yes

token_marker=$pat_name:none
if [ -n "$pat" ]; then
    write_private "$token" "$pat"
    token_marker=$pat_name
elif $prune; then
    rm -f "$token"
    log "$cipher has no $pat_name; removed $token"
else
    log "$cipher has no $pat_name; leaving $token in place (--prune removes it)"
fi

mkdir -p "$(dirname "$state")"
printf '%s %s %s\n' "$want" "$token_marker" "$ssh_key_marker" >"$state"
log "wrote $secrets"
