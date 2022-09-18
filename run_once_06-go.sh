#!/bin/sh

# DEPS: curl, chmod

export GOPATH=~/.go

# Install the gobrew go version manager
curl -sLk https://git.io/gobrew | sh

# Use the latest go version
~/.gobrew/bin/gobrew use latest

# Install tools from source
~/.gobrew/current/bin/go install github.com/charmbracelet/gum@latest

# Install tools from packages (faster)
sudo pacman -S --noconfirm fzf jq glow gopls
