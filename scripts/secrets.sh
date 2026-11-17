#!/bin/sh
# Materialize the single SOPS secrets file: the agent provider keys go to
# ~/.config/secrets.env, and the machine's one GitHub token to
# ~/.config/github-token, which zsh exports as GH_TOKEN. One decrypt covers
# both, so bootstrap prompts for the age passphrase once.
set -eu

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cipher=${DOTFILES_SECRETS:-$root/sops.yaml}
config=${XDG_CONFIG_HOME:-$HOME/.config}
secrets=$config/secrets.env
token=$config/github-token
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
have=${state_line%% *}
token_marker=${state_line#* }
if [ "$want" = "$have" ] && [ -s "$secrets" ]; then
    # A restored or copied file can lose its mode; repair it on every run.
    chmod 600 "$secrets"
    case $token_marker in
        "$pat_name:none") exit 0 ;;
        "$pat_name") [ -s "$token" ] && { chmod 600 "$token"; exit 0; } ;;
    esac
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

mkdir -p "$(dirname "$state")"
printf '%s %s\n' "$want" "$token_marker" >"$state"
log "wrote $secrets"
