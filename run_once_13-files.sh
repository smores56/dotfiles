#!/bin/sh

# DEPS: pacman, go, cargo

# Install file managers
sudo pacman -S --noconfirm thunar
~/.gobrew/current/bin/go install github.com/gokcehan/lf@latest

# Install trash CLI
~/.cargo/bin/cargo install trashy

# Install TUI image viewer
sudo pacman -S --noconfirm chafa

# Install file previewer
sudo rm -rf /tmp/ctpv
git clone https://github.com/NikitaIvanovV/ctpv /tmp/ctpv
sudo make -C /tmp/ctpv install