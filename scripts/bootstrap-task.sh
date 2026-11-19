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

# The real zsh binary from the conda tool, never mise's launcher: the launcher
# exports CONDA_* and prepends the conda prefix (its own tput, tic, reset) to
# PATH for every child. The link moves with each version bump.
link_conda_zsh() {
    [ "$(uname -s)" = Linux ] || return 0
    prefix=$(mise where conda:zsh) || die "conda:zsh is not installed; Linux has no other zsh"
    [ -x "$prefix/bin/zsh" ] || die "no zsh binary under $prefix/bin"
    # conda bakes the install prefix into its binaries, so a moved $HOME
    # leaves zsh unable to load its modules. Reinstall at the current path
    # rather than link a shell that cannot start.
    if ! "$prefix/bin/zsh" -fc 'zmodload zsh/parameter' >/dev/null 2>&1; then
        log "conda:zsh at $prefix cannot load its modules; reinstalling"
        mise install --force --yes conda:zsh || die "could not reinstall conda:zsh"
        prefix=$(mise where conda:zsh) || die "conda:zsh is not installed"
        [ -x "$prefix/bin/zsh" ] || die "no zsh binary under $prefix/bin"
    fi
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$prefix/bin/zsh" "$HOME/.local/bin/zsh"
    log "linked ~/.local/bin/zsh -> $prefix/bin/zsh"
}

# ssh refuses a group- or world-writable ~/.ssh; mise creates parents 0755.
# mise copies the deployed files with the repo's 0644, and ssh refuses a private
# key file that is readable by anyone else. The sk stub holds no secret, but ssh
# cannot tell that, so the mode is tightened after every apply.
tighten_ssh_dir() {
    [ -d "$HOME/.ssh" ] && chmod 700 "$HOME/.ssh"
    [ -f "$HOME/.ssh/id_smortress" ] && chmod 600 "$HOME/.ssh/id_smortress"
    return 0
}

link_conda_zsh
sh "$(dirname "$0")/zim-build.sh" || die "zim build failed; the shell has no plugins until it succeeds"
tighten_ssh_dir
sh "$(dirname "$0")/secrets.sh" \
    || log "secrets refresh failed; run scripts/secrets.sh by hand to see why"
