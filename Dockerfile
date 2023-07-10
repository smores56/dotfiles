FROM docker.io/library/alpine:edge

# Install extra packages
COPY extra-packages /
RUN apk update && \
    apk upgrade && \
    cat /extra-packages | xargs apk add
RUN rm /extra-packages

# Enable password-less sudo
RUN echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/toolbox

# Copy the os-release file
RUN cp -p /etc/os-release /usr/lib/os-release

# Clear out /media
RUN rm -rf /media

RUN apk add \
  python3 py3-pip go rustup \
  fish helix github-cli git jq \
  openssh openssl curl unzip chafa \
  gcc moreutils cmake

RUN pip install \
  mypy python-lsp-server

RUN echo \
  github.com/charmbracelet/gum@latest \
  github.com/jesseduffield/lazygit@latest \
  github.com/charmbracelet/glow@latest \
  github.com/gokcehan/lf@latest \
  github.com/junegunn/fzf@latest \
  golang.org/x/tools/gopls@latest \
  | xargs -n1 go install

# Install Rust and packages
RUN rustup-init -y --no-modify-path --default-toolchain nightly --component rust-src rust-analyzer
# RUN ~/.cargo/bin/cargo install \
#   zoxide exa ripgrep sd \
#   zellij git-delta bat starship pfetch \
#   felix bat trashy fd-find dua-cli ouch \
#   bottom eva licensor typeracer taplo-cli

# Install fnm (node) and packages
RUN ~/.cargo/bin/cargo install --git https://github.com/shyim/fnm-alpine fnm && ~/.cargo/bin/fnm install --lts
# RUN ~/.cargo/bin/fnm exec --using=lts-latest npm install --global \
#   yarn \
#   yaml-language-server \
#   bash-language-server \
#   svelte-language-server \
#   typescript-language-server \
#   vscode-langservers-extracted \
#   dockerfile-language-server-nodejs

CMD ["fish"]
