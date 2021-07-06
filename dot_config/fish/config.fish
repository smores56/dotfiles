# set TERM if it is not set yet
if test -z $TERM; set -xg TERM xterm; end

# set env vars 
set -xg PATH /usr/local/go/bin $HOME/go/bin $HOME/.cargo/bin $HOME/.local/bin /usr/lib/zig $PATH
set -xg EDITOR edit
set -xg LS_COLORS (cat ~/.config/fish/ls-colors.txt)
set -xg BAT_THEME gruvbox

# include custom functions
source ~/.config/fish/functions/custom.fish

# include abbreviations
source ~/.config/fish/abbreviations.fish

# startup splashes
if status --is-interactive
    # fetch sys info
    f

    # set custom prompt
    set fish_greeting
    zoxide init fish | source
    starship init fish | source
end
