#!/bin/sh

export GOPATH=~/.go
export PATH=$GOPATH/bin:~/.bun/bin/bun:$PATH

PACKAGES=(
  github-cli # Git
  helix chafa # Files
  fish opendoas jq # Shell
  python python-pip erlang # Languages
  gcc moreutils cmake base-devel # Build tools
  openssh openssl openssl-1.1 curl # Networking
)

GRAPHICAL_PACKAGES=(scrot vlc discord alacritty thunar)

RUST_PACKAGES=(
  zoxide exa ripgrep sd # Navigation
  zellij git-delta bat # Shell
  bat trashy fd-find dua-cli ouch # Files
  xh bottom eva licensor typeracer # Misc
)

GO_PACKAGES=(
  github.com/gokcehan/lf@latest
  github.com/junegunn/fzf@latest
  github.com/charmbracelet/gum@latest
  github.com/charmbracelet/glow@latest
  github.com/golang/tools/gopls@latest
  github.com/jesseduffield/lazygit@latest
)

JS_PACKAGES=(
  yaml-language-server
  bash-language-server
  svelte-language-server
  typescript-language-server
  vscode-langservers-extracted
  dockerfile-language-server-nodejs
)

PYTHON_PACKAGES=(pyright protonvpn-cli)

TOOLS_FROM_SOURCE=(
  https://github.com/willeccles/f # Simple sysfetch
  https://github.com/NikitaIvanovV/ctpv # file previewer
)

# Allow doas usage without a password
if ! test -e /etc/doas.conf; then
  echo "permit nopass :wheel" | sudo tee -a /etc/doas.conf
  sudo usermod -a -G wheel "$(whoami)"
  sudo chown root /etc/doas.conf
fi

# Install official Arch packages
doas pacman -S --needed --noconfirm "${PACKAGES[@]}"

# Install AUR helper `yay`
if ! which yay 1>/dev/null; then
  rm -rf /tmp/yay
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay
  makepkg -si --noconfirm
fi

# Install bun and packages
if ! test -e ~/.bun/bin/bun; then
  curl https://bun.sh/install | bash
  bun install --global "${JS_PACKAGES[@]}"
fi

# Install Rust and packages
if ! test -e ~/.cargo/bin/cargo; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path --default-toolchain nightly \
    --component rust-src rust-analyzer
fi
~/.cargo/bin/cargo install "${RUST_PACKAGES[@]}"
~/.cargo/bin/cargo install --git https://github.com/gleam-lang/gleam gleam

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
  ~/.go/current/bin/go install "$package"
done

# Install fly bin
if ! test -e ~/.fly/bin/flyctl; then
  curl -L https://fly.io/install.sh | sh
fi

# Install lean package manager
~/.cargo/bin/cargo install --git https://github.com/leanprover/elan

# Set fish as the default shell
FISH_PATH=/usr/bin/fish
if test "$SHELL" != "$FISH_PATH"; then
  echo "$FISH_PATH" | sudo tee -a /etc/shells
  chsh -s "$FISH_PATH"
fi

# Copy public SSH keys from GitHub
if ! test -e ~/.ssh/authorized_keys; then
  curl -L https://github.com/smores56.keys -o ~/.ssh/authorized_keys
fi

# Install and set up tailscale
doas pacman -S --noconfirm tailscale
if test "$(systemctl is-active tailscaled)" != "active"; then
  doas systemctl enable tailscaled
  doas systemctl start tailscaled
  doas tailscale up
fi

if test -n "$DISPLAY"; then
  # Install GUI apps
  doas pacman -S --noconfirm "${GRAPHICAL_PACKAGES[@]}"

  FONT_PATH=~/.local/share/fonts
  FONT_TMP_PATH=/tmp/CaskaydiaCove.zip
  FONT_URL=https://github.com/ryanoasis/nerd-fonts/releases/download/v2.2.2/CascadiaCode.zip

  # Install CaskaydiaCove Font
  if ! test -e "$FONT_TMP_PATH"; then
    curl -L "$FONT_URL" -o "$FONT_TMP_PATH"
    unzip -o "$FONT_TMP_PATH" -d "$FONT_PATH"
    fc-cache -f
  fi
fi
