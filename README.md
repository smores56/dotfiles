# Dotfiles

This folder contains scripts to set up my [BSPWM][bspwm] environment on 
[EndeavourOS][endeavouros], an [Arch Linux][arch] distro.

I use [Alacritty][alacritty] as my terminal emulator, [Fish][fish] for my shell,
[Helix][helix] for my editor, and [Zellij][zellij] for multitasking, so most of
the config is for those tools. Everything else is for tools I use frequently enough
to want already installed everywhere.

## Install

I use [DotBot][dotbot] to manage my dotfiles, which runs pretty much everything off
of the [install.conf.yaml](./install.conf.yaml) file.

Besides having [git][git] and some version of [Python installed][install python],
you'll need to be able to clone the repo locally, should `ssh-keygen` after and add
the new key to your GitHub account with:

```bash
ssh-keygen -t ed25519 -b 4096 -C <computer name>
# Upload to GitHub manually, or run the following after installing the `github-cli`
gh ssh-key add <public key file> -t <computer name>
```

You can then install everything with:

```bash
git clone git@github.com:smores56/dotfiles.git ~/.dotfiles
~/.dotfiles/install
```

## Post-Install

If you want file syncronization with [pCloud][pcloud], you should install the app [from their site][install pcloud].


[arch]: https://archlinux.org/
[endeavouros]: https://endeavouros.com/
[bspwm]: https://github.com/baskerville/bspwm
[install python]: https://www.python.org/downloads/
[git]: https://git-scm.com/
[dotbot]: https://github.com/anishathalye/dotbot
[alacritty]: https://github.com/alacritty/alacritty
[fish]: https://fishshell.com
[helix]: https://helix-editor.com
[zellij]: https://zellij.dev
[pcloud]: https://www.pcloud.com
[install pcloud]: https://www.pcloud.com/download-free-online-cloud-file-storage.html
