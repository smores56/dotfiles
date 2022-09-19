#!/bin/sh

# DEPS: pacman, cargo

sudo pacman -S --noconfirm wayland wlroots xorg-xwayland # wayland
sudo pacman -S --noconfirm sway swaybg swaylock # sway
sudo pacman -S --noconfirm slurp grim # screenshots
sudo pacman -S --noconfirm wl-clipboard # clipboard
sudo pacman -S --noconfirm light # backlight
sudo pacman -S --noconfirm pipewire pipewire-pulse wireplumber # sound
sudo pacman -S --noconfirm mako # notifications

# Install pipewire for sound
sudo cp ~/.dotfiles/udev/90-backlight.rules /usr/lib/udev/rules.d/

# Install i3status-rust for status bar
~/.cargo/bin/cargo install --git https://github.com/greshake/i3status-rust i3status-rs

# Install tiling
pip install autotiling
