#!/bin/sh
# The `bootstrap` task: the pieces mise does not manage declaratively. Runs on
# every `mise bootstrap`, after tools, so every step is safe to repeat.
set -eu

log() { printf 'bootstrap: %s\n' "$*"; }

# The real zsh binary from the conda tool, never mise's launcher: the launcher
# exports CONDA_* and prepends the conda prefix (its own tput, tic, reset) to
# PATH for every child. The link moves with each version bump.
link_conda_zsh() {
    [ "$(uname -s)" = Linux ] || return 0
    prefix=$(mise where conda:zsh 2>/dev/null) || { log "conda:zsh is not installed; skipping the zsh link"; return 0; }
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

link_conda_zsh
install_sdlc
