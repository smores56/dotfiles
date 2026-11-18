#!/bin/sh
# Materialize the single SOPS secrets file: the agent provider keys go to
# ~/.config/secrets.env, the machine's one GitHub token to
# ~/.config/github-token, which zsh exports as GH_TOKEN, and the Cloudflare
# Access service token to ~/.config/cloudflare/access.env, which only the
# smortress-ssh wrapper reads. One decrypt covers all three, so bootstrap
# prompts for the age passphrase once.
#
# The Access pair is a credential for the SSH route, not a provider key: it
# stays out of ~/.config/secrets.env so that nothing which reads the Maki cache
# ever holds it.
set -eu

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cipher=${DOTFILES_SECRETS:-$root/sops.yaml}
config=${XDG_CONFIG_HOME:-$HOME/.config}
secrets=$config/secrets.env
token=$config/github-token
access=$config/cloudflare/access.env
key=$config/sops/keys.age
state=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/secrets.sha256

log() { printf 'secrets: %s\n' "$*"; }

[ -f "$cipher" ] || exit 0
[ -r "$key" ] || { log "no $key on this machine; leaving the secrets alone"; exit 0; }

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

# One token per machine: the work PAT where the work environment is applied,
# the personal PAT everywhere else.
case ",${MISE_ENV-}," in
    *,work,*) pat_name=GITHUB_WORK_PAT ;;
    *) pat_name=GITHUB_PERSONAL_PAT ;;
esac

want=$(sha256_of "$cipher")
state_line=$(cat "$state" 2>/dev/null || true)
have=
token_marker=
access_marker=
if [ -n "$state_line" ]; then
    # <cipher sha> <token marker> <access marker>. A state file written before
    # the Access token existed carries two fields, so the empty access marker
    # makes this run decrypt once more and deliver the token.
    read -r have token_marker access_marker _rest <<EOF
$state_line
EOF
fi
if [ "$want" = "$have" ] && [ -s "$secrets" ]; then
    # A restored or copied file can lose its mode; repair it on every run.
    chmod 600 "$secrets"
    token_ok=no
    case $token_marker in
        "$pat_name:none") token_ok=yes ;;
        "$pat_name") [ -s "$token" ] && { chmod 600 "$token"; token_ok=yes; } ;;
    esac
    access_ok=no
    case $access_marker in
        none) access_ok=yes ;;
        yes) [ -s "$access" ] && { chmod 600 "$access"; access_ok=yes; } ;;
    esac
    if [ "$token_ok" = yes ] && [ "$access_ok" = yes ]; then
        exit 0
    fi
fi

if [ -x "$HOME/.local/bin/sops-age-key" ]; then
    SOPS_AGE_KEY_CMD=$HOME/.local/bin/sops-age-key
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
pat=$(value_of "$pat_name")
access_id=$(value_of CLOUDFLARE_ACCESS_CLIENT_ID)
access_secret=$(value_of CLOUDFLARE_ACCESS_CLIENT_SECRET)

if [ -z "$neuralwatt" ] || [ -z "$tinyfish" ]; then
    log "$cipher needs NEURALWATT_API_KEY and TINYFISH_API_KEY; leaving $secrets alone"
    exit 1
fi

umask 077
mkdir -p "$(dirname "$secrets")"
tmp_env=$secrets.tmp.$$
{
    printf 'NEURALWATT_API_KEY=%s\n' "$neuralwatt"
    printf 'TINYFISH_API_KEY=%s\n' "$tinyfish"
} >"$tmp_env"
mv "$tmp_env" "$secrets"
chmod 600 "$secrets"

token_marker=$pat_name:none
if [ -n "$pat" ]; then
    printf '%s\n' "$pat" >"$token.tmp.$$"
    mv "$token.tmp.$$" "$token"
    chmod 600 "$token"
    token_marker=$pat_name
else
    rm -f "$token"
    log "$cipher has no $pat_name; git and gh have no GitHub token"
fi

access_marker=none
if [ -n "$access_id" ] && [ -n "$access_secret" ]; then
    mkdir -p "$(dirname "$access")"
    {
        printf 'CLOUDFLARE_ACCESS_CLIENT_ID=%s\n' "$access_id"
        printf 'CLOUDFLARE_ACCESS_CLIENT_SECRET=%s\n' "$access_secret"
    } >"$access.tmp.$$"
    mv "$access.tmp.$$" "$access"
    chmod 600 "$access"
    access_marker=yes
else
    rm -f "$access"
    log "$cipher has no CLOUDFLARE_ACCESS_CLIENT_ID and CLOUDFLARE_ACCESS_CLIENT_SECRET; smortress-ssh has no service token"
fi

mkdir -p "$(dirname "$state")"
printf '%s %s %s\n' "$want" "$token_marker" "$access_marker" >"$state"
log "wrote $secrets"
