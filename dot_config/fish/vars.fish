set -xg EDITOR helix
set -xg BAT_THEME ansi

set -xg GOPATH ~/.go
set -xg PATH ~/.cargo/bin ~/.local/bin \
    ~/.rustup/toolchains/nightly-x86_64-unknown-linux-gnu/bin \
    ~/.go/bin ~/.gobrew/bin ~/.gobrew/current/bin \
    ~/.fly/bin ~/.bun/bin $PATH

set -xg LS_COLORS (cat ~/.config/fish/ls-colors.txt)
set -xg GUM_CHOOSE_CURSOR_FOREGROUND 3
set -xg WLR_NO_HARDWARE_CURSORS 1
