#!/bin/sh
# Materialize the single SOPS secrets file: the agent provider keys go to
# ~/.config/secrets.env, and the optional PATs become gh's auth. One decrypt
# covers all of them, so bootstrap prompts for the age passphrase once.
set -eu

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cipher=${DOTFILES_SECRETS:-$root/sops.yaml}
config=${XDG_CONFIG_HOME:-$HOME/.config}
secrets=$config/secrets.env
key=$config/sops/keys.age
state=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/secrets.sha256

log() { printf 'secrets: %s\n' "$*"; }

[ -f "$cipher" ] || exit 0
[ -r "$key" ] || { log "no $key on this machine; leaving the secrets alone"; exit 0; }

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

want=$(sha256_of "$cipher")
state_line=$(cat "$state" 2>/dev/null || true)
case $state_line in
    *' '*) have=${state_line%% *} gh_marker=${state_line#* } ;;
    *) have=$state_line gh_marker= ;;
esac
if [ "$want" = "$have" ] && [ -s "$secrets" ]; then
    # A restored or copied cache can lose its mode; repair it on every run.
    chmod 600 "$secrets"
    case $gh_marker in
        none) exit 0 ;;
        gh)
            # gh is a mise tool. Without it on PATH the PAT cannot be applied,
            # so decrypting again would only ask for the passphrase.
            if ! command -v gh >/dev/null 2>&1; then
                exit 0
            fi
            if gh auth status --hostname github.com >/dev/null 2>&1; then
                exit 0
            fi ;;
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
pat=$(value_of GITHUB_PERSONAL_PAT)
# The work PAT reaches gh only where the work environment is applied, and logs
# in last so it is the active account there.
case ",${MISE_ENV-}," in
    *,work,*) work_pat=$(value_of GITHUB_WORK_PAT) ;;
    *) work_pat= ;;
esac

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

gh_login() {
    # The token goes over stdin, never argv or the environment. gh writes
    # only its own hosts.yml, not the tracked config.yml.
    if printf '%s\n' "$1" | gh auth login --with-token --hostname github.com; then
        log "gh authenticated for github.com"
    else
        log "gh auth login failed; run it by hand if gh commands fail"
        exit 1
    fi
}

gh_marker=none
if [ -n "$pat$work_pat" ]; then
    gh_marker=gh
    if command -v gh >/dev/null 2>&1; then
        [ -z "$pat" ] || gh_login "$pat"
        [ -z "$work_pat" ] || gh_login "$work_pat"
    else
        log "gh is not installed; the next bootstrap will retry the PATs"
    fi
fi

mkdir -p "$(dirname "$state")"
printf '%s %s\n' "$want" "$gh_marker" >"$state"
log "wrote $secrets"
