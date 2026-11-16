# Every zsh reads this first; keep it to locating the real config.
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
[ -r "$ZDOTDIR/.zshenv" ] && . "$ZDOTDIR/.zshenv"
