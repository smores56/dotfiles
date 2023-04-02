Dotfiles
========

This folder contains scripts to set up my [Qtile][qtile] environment on [Void Linux][void linux].

I use [Alacritty][alacritty] as my terminal emulator, [Fish][fish] for my shell,
[Helix][helix] for my editor, and [Zellij][zellij] for multitasking, so most of
the config is for those tools. Everything else is for tools I use frequently enough
to want already installed everywhere.

## Install

I use [chezmoi][chezmoi] to manage my dotfiles, and I have a [bootstrap](./bootstrap)
script that runs a full setup on new machines. After making sure you have `sh`, `git`,
and `curl` installed, just run:

```
curl -sSfL bootstrap.sammohr.dev | sh
```

## Post-Install

If you want file syncronization with [pCloud][pcloud], you should install the app [from their site][install pcloud].

You can set an autologin username for the [emptty][emptty] login manager
in the system-wide config as shown in its [README][emptty conf]. This only works if
you add `$USER` to the group `nopasswdlogin`:

```
sudo groupadd nopasswdlogin
sudo usermod -a -G nopasswdlogin $USER
```


[void linux]: https://voidlinux.org/
[qtile]: http://www.qtile.org/
[chezmoi]: https://www.chezmoi.io/
[alacritty]: https://github.com/alacritty/alacritty
[fish]: https://fishshell.com
[helix]: https://helix-editor.com
[zellij]: https://zellij.dev
[emptty]: https://github.com/tvrzna/emptty
[emptty conf]: https://github.com/tvrzna/emptty#etcempttyconf
[pcloud]: https://www.pcloud.com
[install pcloud]: https://www.pcloud.com/download-free-online-cloud-file-storage.html
