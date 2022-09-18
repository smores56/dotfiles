#!/bin/sh

# DEPS: pacman, tee, chown

# Install doas
sudo pacman -S --noconfirm opendoas

# Allow usage without a password
echo "permit nopass :wheel" | sudo tee -a /etc/doas.conf
sudo chown root /etc/doas.conf
