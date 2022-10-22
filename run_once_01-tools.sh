#!/bin/sh

# DEPS: pacman

sudo pacman -S --noconfirm helix # Editor
sudo pacman -S --noconfirm openssh openssl curl # Networking
sudo pacman -S --noconfirm just moreutils cmake # Build tools
sudo pacman -S --noconfirm unzip tar # Archiving