Dotfiles
========

This repo contains config for my Linux environment.

I use [Alacritty][alacritty] as my terminal emulator, [Fish][fish] for my shell,
[Helix][helix] for my editor, and [Zellij][zellij] for multitasking, so most of
the config is for those tools. Everything else is for tools I use frequently enough
to want already installed everywhere.

## Install

I use [chezmoi][chezmoi] to manage my dotfiles, and I install my tools from a container
using [toolbx][toolbx]. You should first ensure you have the following already installed:

- git
- curl
- [toolbox](https://containertoolbx.org/install)

Then run the following:

```sh
# Install dotfiles
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply smores56
# Install the toolbox container
toolbox create --image smores56/smores-arch-toolbox:latest
# Make toolbox simple to invoke
echo 'alias enter "SHELL=/bin/sbin/fish toolbox enter smores-arch-toolbox"' >> ~/.bashrc
```

## Post-Install

You'll probably want to set up your SSH key and GitHub access like this:

```sh
# Create SSH key
if ! test -e ~/.ssh/id_ed25519.pub; then
  mkdir -p ~/.ssh
  ssh-keygen -t ed25519 -b 4096 -C $(hostname)
fi

# Log in to GitHub via CLI
gh auth login --git-protocol=ssh --scopes=admin:public_key

# Add SSH key to GitHub
PUBLIC_KEY=$(cat ~/.ssh/id_ed25519.pub | cut -d " " -f 2)
if ! curl -L https://github.com/smores56.keys | grep "$PUBLIC_KEY" 1>/dev/null; then
  gh ssh-key add ~/.ssh/id_ed25519.pub -t "$(hostname)"
fi

# Use SSH auth for dotfiles repo
cd $(chezmoi source-path)
git remote set-url origin git@github.com:smores56/dotfiles.git
```

If you want file syncronization with [pCloud][pcloud], you should install the app [from their site][install pcloud].


[toolbx]: https://containertoolbx.org/
[chezmoi]: https://www.chezmoi.io/
[alacritty]: https://github.com/alacritty/alacritty
[fish]: https://fishshell.com
[helix]: https://helix-editor.com
[zellij]: https://zellij.dev
[pcloud]: https://www.pcloud.com
[install pcloud]: https://www.pcloud.com/download-free-online-cloud-file-storage.html
