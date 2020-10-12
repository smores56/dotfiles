# Setup

This folder contains scripts to set up my environment consistently on any
Ubuntu-derivative linux box.

I use `kitty` as my terminal emulator, `fish` for my shell, `kakoune` for my editor,
and `tmux` for multitasking, so most of the config is for those tools. Everything else
is for tools I use at least on a weekly basis.


## Install

You will need to first install `git`, as well as admin permissions. Once you do that, the following
should do everything you need to set up your system.

```sh
cd ~
git clone --bare https://github.com/smores56/dotfiles.git ~/.dotfiles
alias dotfiles="git --git-dir=$HOME/.dotfiles --work-tree=$HOME"
dotfiles reset --hard
dotfiles submodule update --init --recursive
cd ~/.setup/ && sh install.sh
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
_you'll have to update `kitty`'s [config file][kitty config] to use it instead.)_


### Optional

You can install the `kitty` terminal emulator by running `sudo apt install kitty`.

If you want file syncronization with MEGA, you can install MEGASync [here][megasync].

If you want to switch escape and caps lock, you can `sudo apt install gnome-tweaks` and
under "Keyboard & Mouse -> Additional Layout Options -> Caps Lock Behavior" toggle the
"Swap ESC and Caps lock" option.


### Troubleshooting

If one of your SSH servers doesn't support the `kitty` terminal (maybe you ran into something
like `open terminal failed: missing or unsuitable terminal: xterm-kitty`), you can run
`kitty +kitten ssh myserver` to add kitty support.



[kitty config]: ../.config/kitty/kitty.conf
[megasync]: https://mega.nz/sync
[nerd-font]: https://www.nerdfonts.com/font-downloads
