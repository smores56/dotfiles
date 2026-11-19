#!/bin/sh
# The `bootstrap` task: the pieces mise does not manage declaratively. Runs on
# every `mise bootstrap`, after tools, so every step is safe to repeat.
set -eu

log() { printf 'bootstrap: %s\n' "$*"; }
die() { printf 'bootstrap: %s\n' "$*" >&2; exit 1; }

# The task shell inherits the caller's PATH, which on a fresh machine does not
# yet include ~/.local/bin, where install-mise.sh put mise, or mise's shims,
# where the tools live when the caller did not activate mise (secrets.sh needs
# gh, for one).
PATH=$HOME/.local/bin:$HOME/.local/share/mise/shims:$PATH
export PATH

# ssh refuses a group- or world-writable ~/.ssh; mise creates parents 0755.
# mise copies the deployed files with the repo's 0644, and ssh refuses a private
# key file that is readable by anyone else. The sk stub holds no secret, but ssh
# cannot tell that, so the mode is tightened after every apply.
tighten_ssh_dir() {
    [ -d "$HOME/.ssh" ] && chmod 700 "$HOME/.ssh"
    [ -f "$HOME/.ssh/id_smortress" ] && chmod 600 "$HOME/.ssh/id_smortress"
    return 0
}

# The ~/.dotfiles link is bootstrap.sh's job, but it is the one piece of that
# install a later move can drop, and a missing link breaks mise and every
# instruction that names the canonical path. Re-assert it on a clean-bare
# machine; on the work laptop the script leaves the real clone alone.
link_dotfiles_checkout() {
    [ "$(uname -s)" = Linux ] || return 0
    sh "$(dirname "$0")/link-dotfiles-checkout.sh" \
        || log "dotfiles link unchanged; see scripts/link-dotfiles-checkout.sh"
}

link_dotfiles_checkout
tighten_ssh_dir
sh "$(dirname "$0")/secrets.sh" \
    || log "secrets refresh failed; run scripts/secrets.sh by hand to see why"
