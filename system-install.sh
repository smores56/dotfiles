#!/bin/bash

set -e

export GOPATH=~/.go
export PATH=$GOPATH/current/bin:~/.bun/bin/bun:~/.cargo/bin:~/.local/bin/:$PATH

PACKAGES=(
  helix gopls # Editing
  ouch unzip # Archiving
  glow bat # Viewing files
  github-cli lazygit delta # Git
  zoxide exa ripgrep fd # Navigation
  chafa lf trash-cli dua-cli # Files
  python3 python3-pip rustup # Languages
  gcc moreutils cmake base-devel # Build tools
  fish-shell opendoas jq zellij fzf sd # Shell
  openssh openssl curl xh tailscale NetworkManager # Networking
  xdg-desktop-portal xdg-user-dirs xdg-utils # XDG
  bottom eva licensor vsv # Misc
)

# TODO: add flatpak-hosted terminal
GRAPHICAL_PACKAGES=(
  bspwm sxhkd # Window Manager
  xorg-minimal elogind dbus-elogind-x11 # Session
  font-awesome6 font-iosevka fonts-roboto-ttf # Fonts
  polybar feh picom scrot slock alacritty dunst rofi xsel # Misc
  pavucontrol bluez numlockx xbacklight # Peripherals
)

FLATPAKS=(
  app/org.mozilla.firefox/x86_64/stable
  app/com.discordapp.Discord/x86_64/stable
  app/org.videolan.VLC/x86_64/stable
  app/org.kde.dolphin/x86_64/stable
)
FLATHUB_FLATPAKS=(
  org.libreoffice.LibreOffice
  org.cubocore.CoreFM
)

RUST_PACKAGES=(typeracer)
PYTHON_PACKAGES=(pyright protonvpn-cli yq python-rofi)
GO_PACKAGES=(github.com/charmbracelet/gum@latest)
JS_PACKAGES=(
  yaml-language-server
  bash-language-server
  svelte-language-server
  typescript-language-server
  vscode-langservers-extracted
  dockerfile-language-server-nodejs
)

TOOLS_FROM_SOURCE=(
  https://github.com/willeccles/f # Simple sysfetch
  https://github.com/soystemd/lfutils # File previews
)

# Allow doas usage without a password
if ! test -e /etc/doas.conf; then
  echo "permit nopass :wheel" | sudo tee -a /etc/doas.conf
  sudo usermod -a -G wheel "$(whoami)"
  sudo chown root /etc/doas.conf
fi

# Install official Void packages
doas xbps-install -Sy "${PACKAGES[@]}"

# Install bun and packages
if ! test -e ~/.bun/bin/bun; then
  curl https://bun.sh/install | bash
  bun install --global "${JS_PACKAGES[@]}"
fi

# Install Rust and packages
if ! test -e ~/.cargo/bin/cargo; then
  rustup -y --no-modify-path --default-toolchain nightly \
    --component rust-src rust-analyzer
fi
cargo install "${RUST_PACKAGES[@]}"

# Install Python packages
pip install "${PYTHON_PACKAGES[@]}"

# Install tools from source
for tool in "${TOOLS_FROM_SOURCE[@]}"; do
  name=$(basename "$tool")
  if ! which $(basename $name); then
    rm -rf "/tmp/$name"
    git clone "$tool" "/tmp/$name"
    doas make -C "/tmp/$name" install
  fi
done

# Install golang and packages
if ! test -e ~/.go/current/bin/go; then
  curl -sSf https://raw.githubusercontent.com/owenthereal/goup/master/install.sh | \
    sh -s -- '--skip-prompt'
fi
for package in "${GO_PACKAGES[@]}"; do
  go install "$package"
done

# Install fly bin
if ! test -e ~/.fly/bin/flyctl; then
  curl -L https://fly.io/install.sh | sh
fi

# Install lean package manager
cargo install --git https://github.com/leanprover/elan

# Set fish as the default shell
FISH_PATH=$(which fish)
if test "$SHELL" != "$FISH_PATH"; then
  if ! grep "$FISH_PATH" /etc/shells; then
    echo "$FISH_PATH" | sudo tee -a /etc/shells
  fi
  chsh -s "$FISH_PATH"
fi

# Copy public SSH keys from GitHub
if ! test -e ~/.ssh/authorized_keys; then
  curl -L https://github.com/smores56.keys -o ~/.ssh/authorized_keys
fi

# Set up tailscale
if test "$(sv check tailscaled)" != "active"; then
  doas vsv enable tailscaled
  doas vsv start tailscaled
  doas tailscale up
fi

if test -n "$DISPLAY"; then
  # Install GUI apps
  doas xbps-install -Sy "${GRAPHICAL_PACKAGES[@]}"
  flatpak install -y "${FLATPAKS[@]}"
  doas flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  flatpak install -y flathub "${FLATHUB_FLATPAKS[@]}"

  FONT_PATH=~/.local/share/fonts
  FONT_TMP_PATH=/tmp/CaskaydiaCove.zip
  FONT_URL=https://github.com/ryanoasis/nerd-fonts/releases/download/v2.2.2/CascadiaCode.zip
  FONT_NAME="Caskaydia Cove Nerd Font Complete"

  # Install CaskaydiaCove Font
  if ! (fc-list | grep "$FONT_NAME" 1>/dev/null); then
    curl -L "$FONT_URL" -o "$FONT_TMP_PATH"
    unzip -o "$FONT_TMP_PATH" -d "$FONT_PATH"
    fc-cache -f
  fi

  # Set default theme if missing
  if fish -c 'test -z "$THEME"'; then
    set-theme dark
  fi
fi
