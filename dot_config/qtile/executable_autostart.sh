#!/bin/sh

~/.cargo/bin/pueued &
~/.local/bin/pcloud &
dunst &
picom -b &
udiskie &
~/.local/bin/low-bat-notifier &
xset r rate 200 30
