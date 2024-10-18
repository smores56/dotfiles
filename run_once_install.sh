#!/bin/bash

set -ex

ARCH_PACKAGES=(
  python3 python-pip go rust fnm-bin terraform # Languages
  gcc moreutils cmake base-devel               # Build tools
  zoxide ripgrep sd fzf                        # Navigation
  zellij yazi glow helix                       # Explore
  openssh openssl curl bandwhich               # Networking
  bat fd dua-cli ouch file trash-cli           # Files
  k9s docker-compose oxker-bin                 # Containers
  fish pfetch-rs-bin eza                       # Shell
  zip unzip ouch jq                            # Processing
  gnupg pinentry xsel wl-clipboard gum         # Shell I/O
  git git-lfs github-cli git-delta difftastic lazygit gitui # Git
  bottom eva tokei cbonsai-git typeracer-bin aws-cli-v2     # Misc
  mypy python-lsp-server rust-analyzer taplo-cli            # LSP
  gopls typst-lsp typstyle-bin marksman nixpkgs-fmt nil-git # LSP
)

JS_PACKAGES=(
  yarn
  yaml-language-server
  bash-language-server
  svelte-language-server
  @prisma/language-server
  typescript-language-server
  vscode-langservers-extracted
  graphql-language-service-cli
  dockerfile-language-server-nodejs
)

# Install Arch packages
paru -S --noconfirm --needed "${ARCH_PACKAGES[@]}"

# Install JS packages
fnm install --lts
fnm exec --using=lts-latest npm install --global "${JS_PACKAGES[@]}"
