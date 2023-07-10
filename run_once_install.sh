#!/bin/bash

set -e

FLATHUB_PACKAGES=(
  org.wezfurlong.wezterm
  com.discordapp.Discord
  org.videolan.VLC
  org.kicad.KiCad
  org.libreoffice.LibreOffice
  org.gimp.GIMP
)

# Install PaperWM
PAPERWM_DEST=~/.local/share/gnome-shell/extensions/paperwm@hedning:matrix.org
if test ! -d "$PAPERWM_DEST"; then
  git clone https://github.com/paperwm/PaperWM/ "$PAPERWM_DEST"
fi

# Copy public SSH keys from GitHub
mkdir -p ~/.ssh
curl -L https://github.com/smores56.keys -o ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

if test $(chezmoi data | jq ".isHeadless") = "false"; then
  flatpak install flathub --assumeyes "${FLATHUB_PACKAGES[@]}"
fi
