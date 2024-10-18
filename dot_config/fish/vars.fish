set -xg GOPATH ~/.go
set -xg PATH ~/.cargo/bin ~/.rustup/toolchains/*/bin ~/.local/bin \
    ~/.go/bin /usr/local/bin /opt/homebrew/bin $PATH

set -xg BAT_THEME ansi
set -xg LS_COLORS (cat ~/.config/fish/ls-colors.txt)
set -xg GUM_CHOOSE_CURSOR_FOREGROUND 3
set -xg EDITOR helix
