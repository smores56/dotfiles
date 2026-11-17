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

# The sdlc CLI from the private upstream, pinned by commit so a moved tag cannot
# change what is installed. Skipped when another manager already provides it
# (home-manager on smoreswork), so the two never shadow each other.
SDLC_UPSTREAM=git+ssh://git@github.com/smores56/sdlc
SDLC_REV=6f6dde8caf7c7049fc5bb1009261410fa8f0eb44
install_sdlc() {
    if [ -n "${DOTFILES_SKIP_SDLC-}" ]; then
        log "sdlc is not installed on this machine (DOTFILES_SKIP_SDLC)"
        return 0
    fi
    existing=$(command -v sdlc 2>/dev/null || true)
    case $existing in
        ''|"$HOME/.local/bin/sdlc") ;;
        *) log "sdlc comes from $existing; not installing"; return 0 ;;
    esac
    pin="$SDLC_UPSTREAM@$SDLC_REV"
    if uv tool install --quiet --force "$pin"; then
        log "sdlc at $SDLC_REV"
    else
        log "could not install sdlc (the upstream is private: needs a GitHub SSH credential)"
    fi
}

# ssh refuses a group- or world-writable ~/.ssh; mise creates parents 0755.
tighten_ssh_dir() {
    [ -d "$HOME/.ssh" ] && chmod 700 "$HOME/.ssh"
    return 0
}

link_conda_zsh
sh "$(dirname "$0")/zim-build.sh" || die "zim build failed; the shell has no plugins until it succeeds"
tighten_ssh_dir
sh "$(dirname "$0")/agent-secrets.sh" \
    || log "provider keys not refreshed; maki keeps the existing ~/.config/secrets.env"
install_sdlc
