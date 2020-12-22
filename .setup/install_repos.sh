#!/bin/bash

# crystal repo
curl -sSL https://dist.crystal-lang.org/apt/setup.sh | sudo bash

# gh repo
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-key C99B11DEB97541F0
sudo apt-add-repository -y https://cli.github.com/packages

# lazygit repo
sudo add-apt-repository -y ppa:lazygit-team/release
