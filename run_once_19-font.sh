#!/bin/sh

# DEPS: curl, unzip, fc-cache

FONT_URL=https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/JetBrainsMono.zip
FONT_TMP_PATH=/tmp/JetBrainsMono.zip
FONT_PATH=~/.local/share/fonts

# Download the font to /tmp
curl -L "$FONT_URL" -o "$FONT_TMP_PATH"

# Install the font to FONT_PATH and register it
mkdir -p "$FONT_PATH"
unzip -o "$FONT_TMP_PATH" -d "$FONT_PATH"
fc-cache -f
