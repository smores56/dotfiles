# Dotfiles

This folder contains scripts to set up my environment consistently on any
Ubuntu-derivative linux box.

I use `alacritty` as my terminal emulator, `fish` for my shell, `kakoune` for my editor,
and `tmux` for multitasking, so most of the config is for those tools. Everything else
is for tools I use at least on a weekly basis.


## Install

You'll need `sh`, `git`, `tar`, `xargs`, `curl`, and `chezmoi` (the dotfile manager I use)
installed before you can get going. You can install `chezmoi` with the following one-liner:

```console
$ curl -sfL "https://git.io/chezmoi" | sh -s -- -b ~/.local/bin/
```

Once you have those installed, you can clone this repo to your machine with

```console
$ chezmoi init git@github.com:smores56/dotfiles.git
```

and then install my tools with

```console
$ cd ~/.local/share/chezmoi/install
$ sh run.sh
```

All together, that looks like this:

```sh
curl -sfL "https://git.io/chezmoi" | sh -s -- -b ~/.local/bin/
chezmoi init git@github.com:smores56/dotfiles.git
cd ~/.local/share/chezmoi/install
sh run.sh
```

## Post-Install

Make sure to run `Ctrl-B + I` in `tmux` to install all of the plugins used there,
including the "gruvbox" theme.

Also remember to install all of the provided `kakoune` plugins by running `:plug-install`
in `kakoune`'s command mode.

This repo is setup for the `fish` shell, which you can permanently switch to with:

```sh
echo /usr/bin/fish | sudo tee -a /etc/shells
chsh -s /usr/bin/fish
```

Make sure to install a [Nerd font][nerd-font] to ensure that kakoune, tmux, and starship
all work properly. "FiraCode Mono" works pretty well. _(If you don't use that font,_
_you'll have to update `alacritty`'s [config file][alacritty config] to use it instead.)_


### Optional

You can install the `alacritty` terminal emulator by running `sudo apt install alacritty`.

If you want file syncronization with MEGA, you can install MEGASync [here][megasync].


[megasync]: https://mega.nz/sync
[nerd-font]: https://www.nerdfonts.com/font-downloads
[alacritty config]: ../.config/alacritty/dark.yml
