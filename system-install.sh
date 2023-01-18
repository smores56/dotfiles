#!/bin/sh

set -e

export GOPATH=~/.go
export PATH=$GOPATH/bin:$GOPATH/current/bin:~/.bun/bin/:$PATH

ARCH_PACKAGES=$(sh ~/.dotfiles/arch-packages.sh | tr '\n' ' ')

RUST_PACKAGES=(
  zoxide exa ripgrep sd # Navigation
  zellij git-delta bat starship # Shell
  bat trashy fd-find dua-cli ouch # Files
  xh bottom eva licensor typeracer # Misc
)

RUST_GIT_PACKAGES=(
  https://github.com/gleam-lang/gleam
  https://github.com/leanprover/elan
)

GO_PACKAGES=(
  github.com/gokcehan/lf@latest
  github.com/junegunn/fzf@latest
  github.com/charmbracelet/gum@latest
  github.com/charmbracelet/glow@latest
  golang.org/x/tools/gopls@latest
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

# Install doas
if ! which doas 2>/dev/null; then
  sudo pacman -S --noconfirm opendoas
fi

# Allow doas usage without a password
if ! test -e /etc/doas.conf; then
  echo "permit nopass :wheel" | sudo tee -a /etc/doas.conf
  sudo usermod -a -G wheel "$(whoami)"
  sudo chown root /etc/doas.conf
fi

# Mark all current packages as dependencies
if $(pacman -Qe | wc -l) -gt 0; then
  doas pacman -D --asdeps $(pacman -Qe)
fi

# Install Arch packages
doas pacman -S --needed --noconfirm --asexplicit ${ARCH_PACKAGES[@]}

# Install AUR helper `yay`
if ! which yay 1>/dev/null; then
  rm -rf /tmp/yay
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay
  makepkg -si --noconfirm
fi

# Remove orphaned packages
# doas pacman -Rsunc $(pacman -Qtdq; pacman -Qtdgq)

# Install bun
if ! which bun 2>/dev/null; then
  curl https://bun.sh/install | bash
fi

# Install JS packages
bun install --global "${JS_PACKAGES[@]}"

# Install Rust
if ! test -e ~/.cargo/bin/cargo; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
    sh -s -- -y --no-modify-path --default-toolchain nightly \
    --component rust-src rust-analyzer
fi

# Install Rust packages
~/.cargo/bin/cargo install "${RUST_PACKAGES[@]}"
for crate in "${RUST_GIT_PACKAGES[@]}"; do
  ~/.cargo/bin/cargo install --git $crate "$(basename $crate)"
done

# Install Python packages
pip install "${PYTHON_PACKAGES[@]}"

# Install golang
if ! test -e ~/.go/current/bin/go; then
  curl -sSf https://raw.githubusercontent.com/owenthereal/goup/master/install.sh | \
    sh -s -- '--skip-prompt'
fi

# Install golang packages
for package in "${GO_PACKAGES[@]}"; do
  go install "$package"
done

# Install tools from source
for tool in "${TOOLS_FROM_SOURCE[@]}"; do
  name=$(basename "$tool")
  if ! which $(basename $name); then
    rm -rf "/tmp/$name"
    git clone "$tool" "/tmp/$name"
    doas make -C "/tmp/$name" install
  fi
done

# Install fly
if ! test -e ~/.fly/bin/flyctl; then
  curl -L https://fly.io/install.sh | sh
fi

# Set fish as the default shell
FISH_PATH=$(which fish)
if test "$SHELL" != "$FISH_PATH"; then
  echo "$FISH_PATH" | sudo tee -a /etc/shells
  chsh -s "$FISH_PATH"
fi

# Copy public SSH keys from GitHub
if ! test -e ~/.ssh/authorized_keys; then
  curl -L https://github.com/smores56.keys -o ~/.ssh/authorized_keys
fi

# Set up tailscale
if test "$(systemctl is-active tailscaled)" != "active"; then
  doas systemctl enable tailscaled
  doas systemctl start tailscaled
  doas tailscale up
fi
