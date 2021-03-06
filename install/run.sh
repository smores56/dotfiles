#!/bin/bash

echo "add crystal repository..."
curl -fsSL https://crystal-lang.org/install.sh | sudo bash

echo "install jq..."
sudo curl -L https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o /usr/local/bin/jq && \
    sudo chmod +x /usr/local/bin/jq

echo "install packages..."
sudo apt update
jq '.packages[]' config.json | xargs sudo apt install -y

echo "install Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain=nightly --profile=default --component=rust-src,rustfmt

echo "install Go..."
mkdir -p ~/go/bin/
curl -L https://golang.org/dl/go1.15.8.linux-amd64.tar.gz | sudo tar -xz -C /usr/local/

echo "install Zig..."
ZIG_INDEX="https://ziglang.org/download/index.json"
ZIG_URL=$(curl $ZIG_INDEX 2>/dev/null | jq -r '.master."x86_64-linux".tarball')
sudo mkdir -p /usr/lib/zig/
curl $ZIG_URL | sudo tar -xf -C /usr/lib/zig/ --strip-components 1

echo "prepare install of packages..."
export PATH=/usr/local/go/bin:$HOME/.cargo/bin:$HOME/.local/bin/:/usr/lib/zig/0.6.0/:$PATH

echo "install Python packages..."
jq '.python[]' config.json | xargs pip3 install

echo "install Rust packages..."
. $HOME/.cargo/env
jq '.rust[]' config.json | xargs cargo install

echo "install Go packages..."
mkdir -p $HOME/go
GOPATH=$HOME/go
jq '.go[]' config.json | xargs -I % GO111MODULE=on go get -v %

echo "install npm with fnm..."
$HOME/.cargo/bin/fnm install --lts

echo "install Javascript packages..."
jq '.js[]' config.json | xargs npm i -g

echo "install starship..."
curl -fsSL https://starship.rs/install.sh | bash -s -- -y

echo "install f sys info..."
gcc f.c -o ~/.local/bin/f
