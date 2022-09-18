#!/bin/sh

# DEPS: curl, pacman, make, git

# Install Alacritty
sudo pacman -S --noconfirm alacritty

# Install starship
curl https://starship.rs/install.sh |
  sh -s -- --yes --bin-dir ~/.local/bin

# Install shell and multiplexer
sudo pacman -S --noconfirm fish zellij

# Install f, a simple sysfetch
rm -rf /tmp/f
git clone https://github.com/willeccles/f /tmp/f
make -C /tmp/f
mv /tmp/f/f ~/.local/bin/
