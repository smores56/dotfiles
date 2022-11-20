set -xg GOPATH ~/.go
set -gx PNPM_HOME ~/.local/share/pnpm
set -xg PATH ~/.cargo/bin ~/.rustup/toolchains/*/bin ~/.local/bin \
    ~/.go/bin ~/.fly/bin ~/.bun/bin ~/.elan/bin ~/.local/share/pnpm $PATH

set -xg BAT_THEME ansi
set -xg LS_COLORS (cat ~/.config/fish/ls-colors.txt)
set -xg GUM_CHOOSE_CURSOR_FOREGROUND 3
set -xg EDITOR (which helix 1>/dev/null 2>/dev/null;
                and echo helix; or echo hx)
