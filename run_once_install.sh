#!/bin/bash

set -e

export GOPATH=~/.go
export PATH=~/.cargo/bin:~/.local/bin:$PATH

PACKAGES=(
  python3 python3-pip go # Languages
  gcc moreutils cmake base-devel # Build tools
  fish-shell opendoas helix github-cli # Shell
  openssh openssl openssl-devel curl tailscale NetworkManager # Networking
  xdg-desktop-portal xdg-user-dirs xdg-utils # XDG
  vsv unzip chafa poppler timg # Misc
)

GRAPHICAL_PACKAGES=(
  bspwm sxhkd # Window Manager
  xorg-minimal elogind dbus-elogind-x11 # Session
  font-awesome6 font-iosevka fonts-roboto-ttf # Fonts
  polybar feh picom scrot slock dunst rofi xsel # Misc
  pavucontrol bluez numlockx xbacklight # Peripherals
  firefox vlc dolphin alacritty # Apps
)

RUST_PACKAGES=(
  zoxide exa ripgrep sd # Navigation
  zellij git-delta bat starship # Shell
  bat trashy fd-find dua-cli ouch # Files
  bottom eva licensor typeracer # Misc
)

PYTHON_PACKAGES=(
  pyright protonvpn-cli jq yq python-rofi
  asciimol
)
GO_PACKAGES=(
  github.com/charmbracelet/gum@latest
  github.com/jesseduffield/lazygit@latest
  github.com/charmbracelet/glow@latest
  github.com/gokcehan/lf@latest
  github.com/junegunn/fzf@latest
  golang.org/x/tools/gopls@latest
  github.com/srevinsaju/zap@latest
)
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
sudo xbps-install -Sy "${PACKAGES[@]}"

# Install Python packages
pip install --quiet "${PYTHON_PACKAGES[@]}"

# Install golang and packages
for package in "${GO_PACKAGES[@]}"; do
  go install "$package"
done

# Install Rust and packages
if ! which cargo 2>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path --default-toolchain nightly \
    --component rust-src rust-analyzer
fi
cargo install --quiet "${RUST_PACKAGES[@]}"

# Install fnm (node) and packages
if ! which fnm 2>/dev/null; then
  cargo install fnm
fi
if ! $(fnm list | grep lts-latest); then
  fnm install --lts
fi
fnm exec --using=lts-latest npm install --global "${JS_PACKAGES[@]}"

# Install tools from source
for tool in "${TOOLS_FROM_SOURCE[@]}"; do
  name=$(basename "$tool")
  rm -rf "/tmp/$name"
  git clone "$tool" "/tmp/$name"
  sudo make -C "/tmp/$name" install
done

# Install fly bin
if ! which fly 2>/dev/null; then
  curl -L https://fly.io/install.sh | sh
fi

# Set fish as the default shell
FISH_PATH=$(which fish)
if test "$SHELL" != "$FISH_PATH"; then
  if ! grep "$FISH_PATH" /etc/shells; then
    echo "$FISH_PATH" | sudo tee -a /etc/shells
  fi
  sudo chsh -s "$FISH_PATH" $(whoami)
fi

# Copy public SSH keys from GitHub
if ! test -e ~/.ssh/authorized_keys; then
  curl -L https://github.com/smores56.keys -o ~/.ssh/authorized_keys
fi

# Set up tailscale
if test "$(sv check tailscaled)" != "active"; then
  sudo vsv enable tailscaled
  sudo vsv start tailscaled
  sudo tailscale up
fi

if test -n "$DISPLAY"; then
  # Install GUI apps
  sudo xbps-install -Sy "${GRAPHICAL_PACKAGES[@]}"

  # Install Discord AppImage
  zap install --github --from=srevinsaju/discord-appImage discord-appimage

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
