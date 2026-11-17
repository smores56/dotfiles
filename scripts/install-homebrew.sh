#!/bin/sh
# install-homebrew.sh: install Homebrew with its official installer on a fresh
# macOS machine. Run it once, in a terminal, before scripts/install-mise.sh:
# the installer needs sudo and the Xcode Command Line Tools, so it cannot run
# unattended inside `mise bootstrap`.
set -eu

die() { printf 'install-homebrew: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = Darwin ] || die "Homebrew is only needed on macOS"
[ "$(id -u)" -ne 0 ] || die "run this as your user, not root: the installer asks for sudo itself"

if command -v brew >/dev/null 2>&1; then
    printf 'install-homebrew: Homebrew is already installed at %s\n' "$(command -v brew)"
    exit 0
fi

# The official installer checks for the Command Line Tools and prompts for the
# sudo password it needs to create /opt/homebrew on Apple Silicon.
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

printf 'install-homebrew: installed; /opt/homebrew/bin is added by the work environment\n'
