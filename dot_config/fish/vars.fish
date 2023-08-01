set -xg GOPATH ~/.go
set -xg PATH ~/.cargo/bin ~/.rustup/toolchains/*/bin ~/.local/bin \
    ~/.go/bin ~/.fly/bin /usr/local/bin /opt/homebrew/bin $PATH

set -xg BAT_THEME ansi
set -xg LS_COLORS (cat ~/.config/fish/ls-colors.txt)
set -xg GUM_CHOOSE_CURSOR_FOREGROUND 3

if which helix 1>/dev/null 2>/dev/null
    set -xg EDITOR helix
else
    set -xg EDITOR hx
end
