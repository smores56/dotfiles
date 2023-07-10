#!/bin/bash

set -e

ALPINE_PACKAGES=(
  alpine-base sudo util-linux bash
  which procps tree fish less jq helix
  python3 py3-pip go rustup

  gcc moreutils cmake make ninja musl-utils gcompat
  file file-dev chafa git github-cli
  
coreutils diffutils findutils
gnupg keyutils
man-pages mandoc docs ncurses-terminfo bash-completion
openssh-client openssl openssl-dev
curl tailscale rsync
net-tools iproute2 iputils libcap

shadow
zip unzip tar bzip2 xz
)

RUST_PACKAGES=(
  zoxide exa ripgrep sd
  zellij git-delta bat starship pfetch
  felix bat fd-find dua-cli ouch
  bottom eva licensor typeracer taplo-cli
)

PYTHON_PACKAGES=(
  mypy python-lsp-server trash-cli
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

# toolbox create --image quay.io/toolbx-images/alpine-toolbox:edge dev

# cat <<EOF | toolbox enter dev

export GOPATH=~/.go
export PATH=~/.cargo/bin:~/.local/bin:$PATH

sudo apk add ${ALPINE_PACKAGES[@]}
pip install ${PYTHON_PACKAGES[@]}
echo ${GO_PACKAGES[@]} | xargs -n1 go install

rustup-init -y --no-modify-path --default-toolchain nightly --component rust-src rust-analyzer
~/.cargo/bin/cargo install ${RUST_PACKAGES[@]}

~/.cargo/bin/cargo install --git https://github.com/shyim/fnm-alpine fnm && ~/.cargo/bin/fnm install --lts
~/.cargo/bin/fnm exec --using=lts-latest npm install --global ${JS_PACKAGES[@]}

rm -rf /tmp/ctpv
git clone https://github.com/NikitaIvanovV/ctpv /tmp/ctpv
sudo make install -C /tmp/ctpv

# Install tailscale
if ! which tailscale 2>1 1>/dev/null; then
  sudo apk 
  sudo wget https://pkgs.tailscale.com/stable/fedora/tailscale.repo -P /etc/yum.repos.d/
  sudo rpm-ostree install --assumeyes --apply-live tailscale fish
fi
sudo systemctl enable tailscaled
sudo systemctl start tailscaled
sudo tailscale up

# EOF
