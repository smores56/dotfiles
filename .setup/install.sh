#!/bin/bash

echo "install repositories..."
sh install_repos.sh

echo "install packages..."
sudo apt update
sudo apt install jq
jq '.packages[]' config.json | xargs sudo apt install -y

echo "install Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --default-toolchain=nightly --profile=default --component=rust-src,rustfmt

echo "install Go..."
mkdir -p ~/go/bin/
wget -c https://golang.org/dl/go1.15.2.linux-amd64.tar.gz -O - | sudo tar -xz -C /usr/local/

echo "install Zig..."
ZIG_INDEX="https://ziglang.org/download/index.json"
ZIG_URL=$(curl $ZIG_INDEX 2>/dev/null | jq -r '.master."x86_64-linux".tarball')
sudo mkdir -p /usr/lib/zig/
curl $ZIG_URL | sudo tar -xf -C /usr/lib/zig/ --strip-components 1

echo "install Pony..."
PONY_URL="https://raw.githubusercontent.com/ponylang/ponyup/latest-release/ponyup-init.sh"
sh -c "$(curl --proto '=https' --tlsv1.2 -sSf $PONY_URL)"
ponyup update ponyc nightly

echo "prepare install of packages..."
PATH=/usr/local/go/bin:$HOME/.cargo/bin:$HOME/.local/bin/:/usr/lib/zig/0.6.0/:$PATH
NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
. $HOME/.nvm/nvm.sh

echo "install NPM..."
nvm install node && nvm use node

echo "install Python packages..."
jq '.python[]' config.json | xargs pip3 install

echo "install Rust packages..."
. $HOME/.cargo/env
jq '.rust[]' config.json | xargs cargo install

echo "install Go packages..."
mkdir -p $HOME/go
GOPATH=$HOME/go
jq '.go[]' config.json | xargs -I % go get -v %

echo "install Javascript packages..."
jq '.js[]' config.json | xargs xargs npm i -g

echo "install starship..."
curl -fsSL https://starship.rs/install.sh | bash

echo "install rclone..."
curl https://rclone.org/install.sh | sudo bash
