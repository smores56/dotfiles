#!/bin/sh

# DEPS: just, git, cargo, pacman

# Install dependencies for Onagre
sudo pacman -S --noconfirm qalculate-gtk papirus-icon-theme

# Install Pop_OS! launcher
rm -rf /tmp/pop-launcher
git clone https://github.com/pop-os/launcher /tmp/pop-launcher
just --justfile /tmp/pop-launcher/justfile
just --justfile /tmp/pop-launcher/justfile install

# Install launcher wrapper program
~/.cargo/bin/cargo install --git https://github.com/oknozor/onagre
