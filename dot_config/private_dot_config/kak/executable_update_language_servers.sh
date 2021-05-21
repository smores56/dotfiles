#!/bin/bash

# install Rust analyzer
curl -L https://github.com/rust-analyzer/rust-analyzer/releases/latest/download/rust-analyzer-linux -o ~/.local/bin/rust-analyzer
chmod +x ~/.local/bin/rust-analyzer

# install Crystalline
wget https://github.com/elbywan/crystalline/releases/latest/download/crystalline_linux.gz -O ~/.local/bin/crystalline.gz &&\
gzip -d ~/.local/bin/crystalline.gz &&\
chmod u+x ~/.local/bin/crystalline
