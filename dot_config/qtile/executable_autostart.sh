#!/bin/sh

pcloud &
dunst &
picom -b &
~/.local/bin/low-bat-notifier &
xset r rate 320 30
