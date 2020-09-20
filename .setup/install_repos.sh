#!/bin/bash

# zig repo
echo 'deb https://dl.bintray.com/dryzig/zig-ubuntu focal main' | sudo tee -a /etc/apt/sources.list

# gh repo
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-key C99B11DEB97541F0
sudo apt-add-repository -u https://cli.github.com/packages

# vim repo
sudo add-apt-repository ppa:jonathonf/vim

# fonts repo
sudo add-apt-repository universe
