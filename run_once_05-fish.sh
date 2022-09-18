#!/bin/sh

# DEPS: pacman, chsh

# Install fish
sudo pacman -S --noconfirm fish

# Set fish as the default shell
chsh -s /usr/bin/fish