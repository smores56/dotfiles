#!/bin/sh

# DEPS: cargo, pacman

# Update mirrors
sudo cp ~/.local/share/chezmoi/etc/pacman.conf.partial /etc/pacman.conf
sudo chown root /etc/pacman.conf
sudo pacman -Sy
sudo pacman -S --noconfirm artix-archlinux-support
sudo cp ~/.local/share/chezmoi/etc/pacman.conf.final /etc/pacman.conf
sudo chown root /etc/pacman.conf
sudo pacman-key --populate archlinux
sudo pacman -Sy

# AUR helper
~/.cargo/bin/cargo install paru
