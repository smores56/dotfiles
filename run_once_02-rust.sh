#!/bin/sh

# DEPS: curl, pacman

# Install Rust via rustup
curl -L -tlsv1.2 -sSf https://sh.rustup.rs |
  sh -s -- --default-toolchain nightly --no-modify-path -y

# Add default components
~/.cargo/bin/rustup component add rust-src rust-analyzer

# Install crates from source
~/.cargo/bin/cargo install licensor ouch

# Install crates from packages (faster)
sudo pacman -S --noconfirm \
  ripgrep bat bottom dua-cli sd zoxide eva exa fd skim xh
