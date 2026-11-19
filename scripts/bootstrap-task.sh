#!/bin/sh
# The `bootstrap` task: what mise does not manage declaratively. Runs after the
# tools on every `mise bootstrap`, so every step is safe to repeat.
set -eu

log() { printf 'bootstrap: %s\n' "$*" >&2; }

# A fresh machine's caller has neither ~/.local/bin (mise) nor the shims (gh,
# for secrets.sh) on PATH.
PATH=$HOME/.local/bin:${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:$PATH
export PATH

# mise creates ~/.ssh 0755 and copies files 0644; ssh refuses both. The key
# itself is a sops secret, so scripts/secrets.sh owns its mode; this only holds
# the directory and repairs a key delivered under an older mode.
tighten_ssh_dir() {
    [ -d "$HOME/.ssh" ] && chmod 700 "$HOME/.ssh"
    [ -f "$HOME/.ssh/id_smortress" ] && chmod 600 "$HOME/.ssh/id_smortress"
    return 0
}

# The work Mac runs tailscaled unprivileged, so it is a LaunchAgent rather than a
# system daemon: no admin, and it dies with the login session.
load_tailscaled_agent() {
    [ "$(uname -s)" = Darwin ] || return 0
    label=dev.sammohr.tailscaled
    plist=$HOME/Library/LaunchAgents/$label.plist
    [ -f "$plist" ] || return 0
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist" \
        || log "could not load $label; load it with launchctl bootstrap by hand"
}

# ykman is not a mise tool: its pyscard dependency ships no wheel for the PC/SC
# build mise would need, so mise can build no dependency graph and a locked
# install refuses it. uv is mise's, so the version is pinned here instead, and
# only where a smartcard stack exists (macOS ships PC/SC; smorespro has none).
ykman_version=5.9.2
install_ykman() {
    [ "$(uname -s)" = Darwin ] || return 0
    command -v ykman >/dev/null 2>&1 && return 0
    uv tool install --quiet "yubikey-manager==$ykman_version" \
        || log "could not install ykman; run: uv tool install yubikey-manager==$ykman_version"
}

# A moved checkout root drops the ~/.dotfiles link, which every mise command needs.
link_dotfiles_checkout() {
    [ "$(uname -s)" = Linux ] || return 0
    sh "$(dirname "$0")/link-dotfiles-checkout.sh" \
        || log "dotfiles link unchanged; see scripts/link-dotfiles-checkout.sh"
}

link_dotfiles_checkout
tighten_ssh_dir
sh "$(dirname "$0")/secrets.sh" \
    || log "secrets refresh failed; run scripts/secrets.sh by hand to see why"
load_tailscaled_agent
install_ykman
