#!/bin/sh

# DEPS: curl

# Install bun
curl https://bun.sh/install | bash

# Install packages
~/.bun/bin/bun install global \
  svelte-language-server \
  bash-language-server \
  vscode-langservers-extracted \
  typescript-language-server \
  yaml-language-server \
  dockerfile-language-server-nodejs
