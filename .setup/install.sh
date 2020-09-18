#!/bin/bash

echo "install repositories..."
sh install_repos.sh

echo "install packages..."
apt-get update
<packages.txt xargs apt-get install

echo "install Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -- -y --no-modify-path --default-toolchain=nightly --profile=default --components=rust-src,rustfmt

echo "install Go..."
mkdir -p ~/go/bin/
wget -c https://golang.org/dl/go1.15.2.linux-amd64.tar.gz -O - | tar -xz -C /usr/local/ 

echo "install NPM..."
nvm install node && nvm use node

echo "install Rust packages..."
<rust.txt xargs cargo install

echo "install Go packages..."
<go.txt xargs -I % go get % 

echo "install Javascript packages..."
<javascript.txt xargs npm i -g

echo "install starship..."
curl -fsSL https://starship.rs/install.sh | bash

echo "install rclone..."
curl https://rclone.org/install.sh | bash
