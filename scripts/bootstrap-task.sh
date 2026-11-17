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

# kitty's Fedora package ships xterm-kitty only in the letter layout, and the
# ncurses inside the conda zsh resolves only the hashed layout under a
# TERMINFO directory (zellij exports TERMINFO=/usr/lib64/kitty/terminfo).
# Without an entry zsh sees no capabilities at all: setaf, smso, rmso, and
# smkx come back empty, so autosuggestions lose their color and completion
# loses menu highlighting. ncurses reads the hashed layout from ~/.terminfo
# whether or not TERMINFO is set, and the file is tiny, so copy it there.
install_kitty_terminfo() {
    [ "$(uname -s)" = Linux ] || return 0
    src=
    for candidate in /usr/lib64/kitty/terminfo/x/xterm-kitty \
            /usr/share/terminfo/x/xterm-kitty; do
        if [ -f "$candidate" ]; then
            src=$candidate
            break
        fi
    done
    [ -n "$src" ] || return 0
    dst=$HOME/.terminfo/78/xterm-kitty
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        return 0
    fi
    mkdir -p "${dst%/*}"
    cp "$src" "$dst"
    log "installed ${dst#"$HOME"/} so zsh can read the kitty terminal entry"
}

link_conda_zsh
install_kitty_terminfo
sh "$(dirname "$0")/zim-build.sh" || die "zim build failed; the shell has no plugins until it succeeds"
tighten_ssh_dir
sh "$(dirname "$0")/secrets.sh" \
    || log "secrets refresh failed; run scripts/secrets.sh by hand to see why"
