#!/bin/bash

preview="chafa --colors=256 --format=symbols -s $4"

case "$1" in
  *.jpg|*.jpeg) $preview "$1";;
  *.png) $preview "$1";;
  *.gif) $preview "$1";;
  *.tar*) tar tf "$1";;
  *.zip) unzip -l "$1";;
  *.rar) unrar l "$1";;
  *.7z) 7z l "$1";;
  *.pdf) pdftotext "$1" -;;
  *) bat --color=always "$1";;
esac
