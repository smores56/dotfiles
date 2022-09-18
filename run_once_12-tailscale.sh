#!/bin/sh

# DEPS: pacman, openrc

# Install tailscale
sudo pacman -S --noconfirm tailscale tailscale-openrc

# Set up tailscale daemon
sudo rc-update add tailscaled
sudo rc-service tailscaled start