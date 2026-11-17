#!/bin/sh
# Materialize the SOPS-encrypted agent provider keys into ~/.config/secrets.env
# on machines that hold the admin age identity. The ciphertext lives in the
# repository; the plaintext cache is derived and never tracked. smoreswork has
# no age identity, so it leaves the file alone.
#
# The bootstrap task runs this after tools, so sops and age are on PATH.
set -eu

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cipher=${DOTFILES_AGENT_SECRETS:-$root/secrets/agent.yaml}
config=${XDG_CONFIG_HOME:-$HOME/.config}
secrets=$config/secrets.env
key=$config/sops/keys.age
state=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/agent-secrets.sha256

log() { printf 'agent-secrets: %s\n' "$*"; }

[ -f "$cipher" ] || exit 0
[ -r "$key" ] || { log "no $key on this machine; leaving $secrets alone"; exit 0; }

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

want=$(sha256_of "$cipher")
have=$(cat "$state" 2>/dev/null || true)
[ -f "$secrets" ] && [ "$want" = "$have" ] && exit 0

if [ -x "$HOME/.local/bin/sops-age-key" ]; then
    SOPS_AGE_KEY_CMD=$HOME/.local/bin/sops-age-key
    export SOPS_AGE_KEY_CMD
fi

tmp=$secrets.tmp.$$
trap 'rm -f "$tmp"' EXIT HUP INT TERM
umask 077
mkdir -p "$(dirname "$secrets")"
if ! sops --decrypt --output-type dotenv "$cipher" \
        | grep -E '^(NEURALWATT|TINYFISH)_API_KEY=' >"$tmp"; then
    log "sops could not decrypt $cipher; keeping the current $secrets"
    exit 1
fi
grep -q '^NEURALWATT_API_KEY=.' "$tmp" \
    || { log "$cipher has no NEURALWATT_API_KEY"; exit 1; }
grep -q '^TINYFISH_API_KEY=.' "$tmp" \
    || { log "$cipher has no TINYFISH_API_KEY"; exit 1; }

mv "$tmp" "$secrets"
chmod 600 "$secrets"
mkdir -p "$(dirname "$state")"
printf '%s\n' "$want" >"$state"
log "wrote $secrets from $cipher"
