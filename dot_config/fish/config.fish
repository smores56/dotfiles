# set TERM if it is not set yet
if test -z $TERM; set -xg TERM xterm; end

# set env vars 
set -xg PATH /usr/local/go/bin $HOME/go/bin $HOME/.cargo/bin $HOME/.local/bin /usr/lib/zig $PATH
set -xg EDITOR kak-spawn

# include custom functions
source ~/.config/fish/functions/custom.fish

# include abbreviations
source ~/.config/fish/abbreviations.fish

# startup splashes
if status --is-interactive
    # give a splash screen based on whether currently in a tab
    smoresfetch

    # update alacritty theme
    set-alacritty-theme

    # set custom prompt
    set fish_greeting
    zoxide init fish | source
    starship init fish | source
end
