#!/bin/sh

case "$THEME" in
    light)
        echo gruvbox-light
        ;;
    dark)
        echo gruvbox
        ;;
    *)
        currentTime=$(date "+%H")
        if [ $currentTime -ge 7 ] && [ $currentTime -lt 18 ]; then
            echo gruvbox-light
        else
            echo gruvbox
        fi
        ;;
esac
