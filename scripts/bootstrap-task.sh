#!/bin/sh
# The `bootstrap` task: what mise does not manage declaratively. Runs after the
# tools on every `mise bootstrap`, so every step is safe to repeat.
set -eu

log() { printf 'bootstrap: %s\n' "$*" >&2; }

# A fresh machine's caller has neither ~/.local/bin (mise) nor the shims (gh,
# for secrets.sh) on PATH.
PATH=$HOME/.local/bin:${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:$PATH
export PATH

# mise creates ~/.ssh 0755 and copies files 0644; ssh refuses both, even for the
# sk stub, which holds no secret.
tighten_ssh_dir() {
    [ -d "$HOME/.ssh" ] && chmod 700 "$HOME/.ssh"
    [ -f "$HOME/.ssh/id_smortress" ] && chmod 600 "$HOME/.ssh/id_smortress"
    return 0
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
