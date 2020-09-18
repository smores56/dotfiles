# Setup

This folder contains scripts to set up a consistent environment on any Ubuntu-derivative linux box.


## Install

You will need to first install `git`, as well as admin permissions.

First clone this repo into your $HOME directory with:

`git clone --bare https://github.com/smores56/dotfiles.git $HOME/.dotfiles`

Then update all of the submodules:

`git --git-dir=$HOME/.dotfiles --submodule update --init --recursive`

Lastly, run the install script:

`cd ~/.setup/ && sh install.sh`


## Post-Install

You'll want to add everything to your `.bashrc` by putting
`source $HOME/.setup/.bashrc` at the end of your `.bashrc`.

Make sure to install a [Nerd font][nerd-font] to ensure that vim, tmux, and starship
all work properly. "FiraCode Mono" works pretty well. _(If you don't use that font,_
_you'll have to update `alacritty`'s [config file][alacritty config] to use it instead.)_


### Optional

You can install the `alacritty` terminal emulator by running `cargo install alacritty`.

You can install MEGASync [here][megasync], but `nnn` and `rclone` already integrate with MEGA.



[alacritty config]: ../.alacritty.yml
[megasync]: https://mega.nz/sync
[nerd-font]: https://www.nerdfonts.com/font-downloads
