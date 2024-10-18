FROM docker.io/imrehg/archlinux-makepkg:latest

LABEL com.github.containers.toolbox="true" \
      name="smores-arch-toolbox" \
      version="latest" \
      usage="This image is meant to be used with the toolbox(1) command" \
      summary="Image for creating Arch Toolbx containers"

# Install Arch packages
RUN yay -S --noconfirm --needed \
  python3 python-pip go rust terraform fnm-bin $(: Languages) \
  gcc moreutils cmake base-devel               $(: Build tools) \
  zoxide eza ripgrep sd fzf                    $(: Navigation) \
  zellij yazi glow helix                       $(: Explore) \
  openssh openssl curl bandwhich               $(: Networking) \
  bat fd dua-cli ouch file trash-cli           $(: Files) \
  k9s docker docker-compose oxker              $(: Containers) \
  fish pfetch-rs-bin                           $(: Shell) \
  zip unzip ouch jq                            $(: Processing) \
  gnupg pinentry xsel wl-clipboard gum         $(: Shell I/O) \
  git git-lfs github-cli git-delta difftastic lazygit gitui   $(: Git) \
  bottom eva taplo-cli tokei cbonsai typeracer-bin aws-cli-v2 $(: Misc) \
  # Editor tools
  nixpkgs-fmt nil-git mypy python-lsp-server      $(: LSP) \
  rust-analyzer gopls typst-lsp typstyle marksman $(: LSP) \
  # GUI
  ttf-cascadia-code-nerd ttf-nerd-fonts-symbols   $(: Fonts) \
  discord firefox vlc evince thunar alacritty feh $(: Apps) \
  kicad gimp libreoffice-still                    $(: Apps)

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
