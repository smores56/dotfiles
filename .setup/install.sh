#!/bin/bash

echo "install repositories..."
sh install_repos.sh

echo "install packages..."
sudo apt update
<packages.txt xargs sudo apt install -y

echo "install Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -- -y --no-modify-path --default-toolchain=nightly --profile=default --components=rust-src,rustfmt

echo "install Go..."
mkdir -p ~/go/bin/
wget -c https://golang.org/dl/go1.15.2.linux-amd64.tar.gz -O - | sudo tar -xz -C /usr/local/ 

echo "install NPM..."
# load nvm
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install node && nvm use node

echo "install Rust packages..."
<rust.txt xargs cargo install

echo "install Go packages..."
<go.txt xargs -I % go get % 

echo "install Javascript packages..."
<javascript.txt xargs npm i -g

echo "install rclone..."
curl https://rclone.org/install.sh | sudo bash
