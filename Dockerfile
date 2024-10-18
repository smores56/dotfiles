#########
# Builder
#########
FROM archlinux AS base

RUN pacman -Syuq --noconfirm git base-devel sudo

RUN echo "Defaults         lecture = never" > /etc/sudoers.d/privacy \
  && echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel

RUN useradd -m -G wheel builder && \
  cd /home/builder && \
  sudo -su builder git clone https://aur.archlinux.org/paru.git && \
  sudo -su builder makepkg -s --noconfirm -D paru && \
  mv * /tmp/paru && \
  userdel builder -rf

#########
# Runtime
#########
FROM archlinux

LABEL com.github.containers.toolbox="true" \
      name="smores-arch-toolbox" \
      version="latest" \
      usage="This image is meant to be used with the toolbox(1) command" \
      summary="Image for creating Arch Toolbx containers"

RUN pacman -Syuq --noconfirm git base-devel sudo namcap openssh \
 && rm -rf /var/cache/pacman/pkg/*

COPY --from=base /tmp/paru/*.pkg.tar.* /tmp/pkg/

RUN sudo pacman -U --noconfirm /tmp/pkg/*.pkg.tar.*

# Install Arch packages
RUN paru -S --noconfirm --needed \
  # terraform docker github-cli nixpkgs-fmt nil-git eza
  python3 python-pip go rust fnm-bin           $(: Languages) \
  gcc moreutils cmake base-devel               $(: Build tools) \
  zoxide ripgrep sd fzf                        $(: Navigation) \
  zellij yazi glow helix                       $(: Explore) \
  openssh openssl curl bandwhich               $(: Networking) \
  bat fd dua-cli ouch file trash-cli           $(: Files) \
  k9s docker-compose oxker-bin                 $(: Containers) \
  fish pfetch-rs-bin                           $(: Shell) \
  zip unzip ouch jq                            $(: Processing) \
  gnupg pinentry xsel wl-clipboard gum         $(: Shell I/O) \
  git git-lfs git-delta difftastic lazygit gitui        $(: Git) \
  bottom eva tokei cbonsai-git typeracer-bin aws-cli-v2 $(: Misc) \
  mypy python-lsp-server rust-analyzer taplo-cli        $(: LSP) \
  gopls typst-lsp typstyle-bin marksman                 $(: LSP)

# Install JS packages
RUN fnm install --lts && \
  fnm exec --using=lts-latest npm install --global \
  yarn \
  yaml-language-server \
  bash-language-server \
  svelte-language-server \
  @prisma/language-server \
  typescript-language-server \
  vscode-langservers-extracted \
  graphql-language-service-cli \
  dockerfile-language-server-nodejs
