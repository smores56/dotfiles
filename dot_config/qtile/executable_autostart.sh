#!/bin/sh

~/.local/bin/pcloud &
dunst &
picom -b &
udiskie &
~/.local/bin/low-bat-notifier &
xset r rate 320 30
