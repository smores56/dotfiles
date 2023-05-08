#!/bin/bash

set -e

export GOPATH=~/.go
export PATH=~/.cargo/bin:~/.local/bin:$PATH

PACKAGES=(
  python3 python-pip go # Languages
  gcc moreutils cmake base-devel # Build tools
  fish opendoas helix github-cli git jq # Shell
  openssh openssl curl # Networking
  unzip chafa poppler # Misc
)

GRAPHICAL_PACKAGES=(
  feh alacritty flatpak dmenu j4-dmenu-desktop xsel
)

FLATHUB_PACKAGES=(
  org.mozilla.firefox
  com.discordapp.Discord
  org.libreoffice.LibreOffice
  org.videolan.VLC
  org.cubocore.CorePDF
  org.kde.dolphin
  org.kicad.KiCad
  org.gimp.GIMP
)

RUST_PACKAGES=(
  zoxide exa ripgrep sd # Navigation
  zellij git-delta bat starship # Shell
  bat trashy fd-find dua-cli ouch # Files
  bottom eva licensor typeracer taplo-cli # Misc
)

PYTHON_PACKAGES=(
  protonvpn-cli asciimol mypy python-lsp-server
)
GO_PACKAGES=(
  github.com/charmbracelet/gum@latest
  github.com/jesseduffield/lazygit@latest
  github.com/charmbracelet/glow@latest
  github.com/gokcehan/lf@latest
  github.com/junegunn/fzf@latest
  golang.org/x/tools/gopls@latest
)
JS_PACKAGES=(
  yarn
  yaml-language-server
  bash-language-server
  svelte-language-server
  typescript-language-server
  vscode-langservers-extracted
  dockerfile-language-server-nodejs
)

TOOLS_FROM_SOURCE=(
  https://github.com/willeccles/f # Simple sysfetch
  https://github.com/NikitaIvanovV/ctpv # File previews
)

# Allow doas usage without a password
if ! test -e /etc/doas.conf; then
  echo "permit nopass :wheel" | sudo tee -a /etc/doas.conf
  sudo usermod -a -G wheel "$(whoami)"
  sudo chown root /etc/doas.conf
fi

# Install official Arch packages
sudo pacman -Sy --noconfirm "${PACKAGES[@]}"

# Install Python packages
pip install "${PYTHON_PACKAGES[@]}"

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
cargo install "${RUST_PACKAGES[@]}"

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
  if ! which "$name" 2>/dev/null; then
    sudo rm -rf "/tmp/$name"
    git clone "$tool" "/tmp/$name"
    sudo make -C "/tmp/$name" install
  fi
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
mkdir -p ~/.ssh
curl -L https://github.com/smores56.keys -o ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Install tailscale
if ! which tailscale 2>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

# Set up tailscale
sudo systemctl enable tailscaled
sudo systemctl start tailscaled
sudo tailscale up

if test $(chezmoi data | jq ".isHeadless") = "false"; then
  # Install GUI apps
  sudo pacman -Sy --noconfirm "${GRAPHICAL_PACKAGES[@]}"
  sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  sudo flatpak install --assumeyes flathub "${FLATHUB_PACKAGES[@]}"

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
  if ! test -e ~/.theme.yml; then
    fish -c "set-theme dark"
  fi
fi
