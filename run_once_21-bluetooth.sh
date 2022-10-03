#!/bin/sh

# Install Bluetooth
sudo pacman -Sy --noconfirm bluez bluez-utils bluez-openrc

# Enable Bluetooth service
sudo rc-update add bluetoothd
sudo rc-service bluetoothd start

# Install Bluetooth TUI
~/.gobrew/current/bin/go install github.com/darkhz/bluetuith@latest
