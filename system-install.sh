#!/bin/sh

export PATH=~/.go/bin:$PATH

PACKAGES=(
  fish opendoas zellij # Shell
  lazygit git-delta github-cli # Git
  helix glow bat lf chafa trash-cli fd # Files
  fzf skim jq zoxide exa ripgrep sd # Navigation
  rustup go python python-pip npm # Languages
  pyright gopls # LSP's
  unzip tar # Archiving
  just gcc moreutils cmake base-devel # Build tools
  openssh openssl curl xh tailscale # Networking
  gum bottom dua-cli eva # Misc
)

# Install official Arch packages
sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"

# Install AUR helper `yay`
if ! which yay; then
  rm -rf /tmp/yay
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay
  makepkg -si
fi

# Install AUR packages
AUR=(typioca elan-lean license flyctl-bin ctpv-git)
for package in "${AUR[@]}"; do
  if ! pacman -Q "$package"; then
    yay -S --noconfirm "$package"
  fi
done

# Install JS packages
sudo npm install --global \
  svelte-language-server bash-language-server \
  vscode-langservers-extracted typescript-language-server \
  yaml-language-server dockerfile-language-server-nodejs

# Setup Rust
rustup default nightly
rustup component add rust-src rust-analyzer

# Install f, a simple sysfetch
if test -z ~/.local/bin/f; then
  rm -rf /tmp/f
  git clone https://github.com/willeccles/f /tmp/f
  make -C /tmp/f
  mv /tmp/f/f ~/.local/bin/
fi

# Allow doas usage without a password
if test -z /etc/doas.conf; then
  echo "permit nopass :wheel" | sudo tee -a /etc/doas.conf
  sudo usermod -a -G wheel "$(whoami)"
  sudo chown root /etc/doas.conf
fi

# Set fish as the default shell
if [ "$SHELL" != "/usr/bin/fish" ]; then
  chsh -s /usr/bin/fish
fi

# Copy public SSH keys from GitHub
if test -z ~/.ssh/authorized_keys; then
  curl -L https://github.com/smores56.keys -o ~/.ssh/authorized_keys
fi

# Enable services
sudo systemctl enable tailscaled
sudo systemctl start tailscaled
sudo tailscale up

if test -n "$DISPLAY"; then
  # Install GUI apps
  sudo pacman -S --noconfirm vlc discord alacritty thunar

  FONT_PATH=~/.local/share/fonts
  FONT_TMP_PATH=/tmp/JetBrainsMono.zip
  FONT_URL=https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/JetBrainsMono.zip

  # Install JetBrainsMono Font
  if test -z "$FONT_TMP_PATH"; then
    curl -L "$FONT_URL" -o "$FONT_TMP_PATH"
    unzip -o "$FONT_TMP_PATH" -d "$FONT_PATH"
    fc-cache -f
  fi
fi
