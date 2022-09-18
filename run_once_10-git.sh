#!/bin/sh

# DEPS: git, pacman, make, go

# Install git TUI helper and diff viewer
sudo pacman -S --noconfirm lazygit git-delta

# Install GitHub CLI
rm -rf /tmp/gh
git clone https://github.com/cli/cli /tmp/gh
make -C /tmp/gh install prefix=~/.local/
