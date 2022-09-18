#!/bin/sh

while true; do
  wallpaper=$(find ~/Pictures/Wallpapers/* | shuf | head -n 1)
  swaybg --image "$wallpaper" --mode fill

  sleep 10
done