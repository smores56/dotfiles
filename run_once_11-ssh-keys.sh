#!/bin/sh

# DEPS: curl

# Copy public SSH keys from GitHub
mkdir -p ~/.ssh
curl -L https://github.com/smores56.keys -o ~/.ssh/authorized_keys