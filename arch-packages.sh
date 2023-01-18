#!/bin/sh

set -e

# GUI Apps
if test -n "$DISPLAY"; then
  echo \
  firefox deluge-gtk discord \
  gimp kicad openscad libreoffice-still evince \
  alacritty obs-studio kdenlive audacity \
  lollypop vlc soundconverter thunar
fi

# Basics
echo make autoconf automake clang cmake \
htop jq moreutils pkgconf fish

# WM
# echo \
# wdisplays kanshi autotiling \
# grim wl-clipboard clipman wf-recorder \
# wob wofi waybar bemenu-wayland \
# sway swaybg swayidle swaylock swayr \
# wtype wlrobs-hg wlsunset mako

# Editor
echo vi vim helix micro nano

# Archiving
echo gzip zip unrar unzip tar

# Files
echo chafa

# Networking
echo network-manager-applet openssl-1.1 tailscale

# VCS
echo git github-cli

# Containers
echo podman-docker podman-compose

# Fonts
echo \
ttf-dejavu ttf-fantasque-sans-mono ttf-fira-sans ttf-jetbrains-mono \
noto-fonts noto-fonts-cjk noto-fonts-emoji terminus-font freetype2

# Languages
echo python python-pip erlang

# Package Management
echo reflector-simple fwupd downgrade rate-mirrors

# Man Pages
echo man-db man-pages
