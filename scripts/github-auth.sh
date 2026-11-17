#!/bin/sh
# Install a personal GitHub token from SOPS into gh's own store, so a headless
# personal machine needs no interactive `gh auth login`. The work laptop has no
# admin age identity and uses its 1Password gh wrapper instead, so it skips.
set -eu

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cipher=${DOTFILES_GITHUB_SECRETS:-$root/secrets/github.yaml}
config=${XDG_CONFIG_HOME:-$HOME/.config}
key=$config/sops/keys.age
state=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/github-auth.sha256

log() { printf 'github-auth: %s\n' "$*"; }

[ -f "$cipher" ] || exit 0
[ -r "$key" ] || { log "no $key on this machine; leaving gh auth alone"; exit 0; }
command -v gh >/dev/null 2>&1 || { log "gh is not installed; leaving gh auth alone"; exit 0; }

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

want=$(sha256_of "$cipher")
have=$(cat "$state" 2>/dev/null || true)
if [ "$want" = "$have" ] && gh auth status --hostname github.com >/dev/null 2>&1; then
    exit 0
fi

if [ -x "$HOME/.local/bin/sops-age-key" ]; then
    SOPS_AGE_KEY_CMD=$HOME/.local/bin/sops-age-key
    export SOPS_AGE_KEY_CMD
fi

token=$(sops --decrypt --extract '["github-personal-pat"]' "$cipher") \
    || { log "sops could not read github-personal-pat from $cipher"; exit 1; }
[ -n "$token" ] || { log "$cipher has no github-personal-pat"; exit 1; }

# The token goes over stdin, never argv or the environment. gh writes only its
# own hosts.yml; the tracked ~/.config/gh/config.yml is left alone.
printf '%s\n' "$token" | gh auth login --with-token --hostname github.com

mkdir -p "$(dirname "$state")"
printf '%s\n' "$want" >"$state"
log "gh authenticated for github.com"
