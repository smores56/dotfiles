# Dotfiles

This folder contains scripts to set up my [Sway][sway] environment on 
[Artix Linux][artix].

I use [Alacritty][alacritty] as my terminal emulator, [Fish][fish] for my shell,
[Helix][helix] for my editor, and [Zellij][zellij] for multitasking, so most of
the config is for those tools. Everything else is for tools I use at least on
a weekly basis.


## Install

I use [homemaker][homemaker] to manage my dotfiles, which runs pretty much everything off
of the [config.toml](./config.toml) file. You can install it and run the install with:

```bash
mkdir -p ~/.local/bin/
curl -L https://github.com/FooSoft/homemaker/releases/latest/download/homemaker_linux_amd64.tar.gz | tar xzf - -C ~/.local/bin/
git clone https://github/com/smores56/dotfiles ~/.dotfiles
cd ~/.dotfiles
git remote set-url origin git@github.com:smores56/dotfiles.git
./run.sh
```

You should `ssh-keygen` after and add the new key to your GitHub account with:

```bash
gh ssh-key add <public key file> -t <key name>
```


## Post-Install

If you want file syncronization with [pCloud][pcloud], you should install the app [from their site][install pcloud].


[artix]: https://artixlinux.org
[homemaker]: https://github.com/FooSoft/homemaker
[alacritty]: https://github.com/alacritty/alacritty
[sway]: https://swaywm.org
[fish]: https://fishshell.com
[helix]: https://helix-editor.com
[zellij]: https://zellij.dev
[pcloud]: https://www.pcloud.com
[install pcloud]: https://www.pcloud.com/download-free-online-cloud-file-storage.html
