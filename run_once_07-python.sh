#!/bin/sh

# DEPS: pacman

# Install Python 3
sudo pacman -S --noconfirm python python-pip

# Install all packages
pip install lookatme "python-lsp-server[all]"