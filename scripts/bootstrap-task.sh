#!/bin/sh
# The `bootstrap` task: the pieces mise does not manage declaratively. Runs on
# every `mise bootstrap`, after tools, so every step is safe to repeat.
set -eu

log() { printf 'bootstrap: %s\n' "$*"; }
die() { printf 'bootstrap: %s\n' "$*" >&2; exit 1; }

# The task shell inherits the caller's PATH, which on a fresh machine does not
# yet include ~/.local/bin, where install-mise.sh put mise.
PATH=$HOME/.local/bin:$PATH
export PATH

# The real zsh binary from the conda tool, never mise's launcher: the launcher
# exports CONDA_* and prepends the conda prefix (its own tput, tic, reset) to
# PATH for every child. The link moves with each version bump.
link_conda_zsh() {
    [ "$(uname -s)" = Linux ] || return 0
    prefix=$(mise where conda:zsh) || die "conda:zsh is not installed; Linux has no other zsh"
    [ -x "$prefix/bin/zsh" ] || die "no zsh binary under $prefix/bin"
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$prefix/bin/zsh" "$HOME/.local/bin/zsh"
    log "linked ~/.local/bin/zsh -> $prefix/bin/zsh"
}

# ssh refuses a group- or world-writable ~/.ssh; mise creates parents 0755.
tighten_ssh_dir() {
    [ -d "$HOME/.ssh" ] && chmod 700 "$HOME/.ssh"
    return 0
}

link_conda_zsh
sh "$(dirname "$0")/wezterm-appimage.sh" || die "wezterm appimage install failed; there is no terminal without it"
sh "$(dirname "$0")/zim-build.sh" || die "zim build failed; the shell has no plugins until it succeeds"
tighten_ssh_dir
sh "$(dirname "$0")/secrets.sh" \
    || log "secrets refresh failed; run scripts/secrets.sh by hand to see why"
