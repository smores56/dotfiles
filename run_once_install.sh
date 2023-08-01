#!/bin/bash

set -e

export GOPATH=~/.go
export PATH=~/.cargo/bin:~/.local/bin:$PATH

ARCH_PACKAGES=(
  python3 python-pip go # Languages
  gcc moreutils cmake base-devel # Build tools
  fish helix github-cli git jq # Shell
  openssh openssl curl # Networking
  unzip chafa mypy python-lsp-server # Misc
)

OSX_PACKAGES=(
  go gcc fish trash-cli tailscale
  moreutils cmake # Build tools
  fish helix gh jq # Shell
  openssh openssl curl # Networking
  unzip chafa mypy python-lsp-server # Misc
)

GRAPHICAL_ARCH_PACKAGES=(
  xsel acpilight playerctl # Tools
  ttf-cascadia-code-nerd ttf-nerd-fonts-symbols # Fonts
  discord firefox vlc evince thunar alacritty feh # Apps
  kicad gimp libreoffice-still # Apps
)

GRAPHICAL_OSX_PACKAGES=(
  alacritty
)

RUST_PACKAGES=(
  zoxide exa ripgrep sd # Navigation
  zellij git-delta bat starship # Shell
  bat fd-find dua-cli ouch # Files
  bottom eva licensor typeracer taplo-cli gyr # Misc
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

# TODO: allow password-less sudo?

# Install system packages
if test "$(uname)" = "Darwin"; then
  # Install homebrew
  if ! which /opt/homebrew/bin/brew 2>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  brew install "${OSX_PACKAGES[@]}"
else
  sudo pacman -Sy --noconfirm "${ARCH_PACKAGES[@]}"
fi

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
    sudo CFLAGS="-L/opt/homebrew/lib -I/opt/homebrew/include" make -C "/tmp/$name" install
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
if test "$(uname)" != "Darwin" && ! sudo systemctl is-active tailscaled; then
  sudo systemctl enable tailscaled
  sudo systemctl start tailscaled
  sudo tailscale up
fi

if test $(chezmoi data | jq ".isHeadless") = "false"; then
  # Install GUI apps
  if test "$(uname)" = "Darwin"; then
    brew install "${GRAPHICAL_OSX_PACKAGES[@]}"
  else
    sudo pacman -Sy --noconfirm "${GRAPHICAL_ARCH_PACKAGES[@]}"
  fi

  # Set default theme if missing
  if ! test -e ~/.theme.yml; then
    fish -c "set-theme dark"
  fi
fi
