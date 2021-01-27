# set TERM if it is not set yet
if test -z $TERM; set -xg TERM xterm; end

# set env vars 
set -xg PATH /usr/local/go/bin $HOME/go/bin $HOME/.cargo/bin $HOME/.local/bin /usr/lib/zig $PATH
set -xg EDITOR kak

# include custom functions
source ~/.config/fish/functions/custom.fish

# set aliases
alias k="kak"
alias a="amp"
alias t="tmux a 2>/dev/null; tmux new -s main"
alias r="ranger"
alias lg="lazygit"
alias df="lazygit -w $HOME"
alias st="set_theme"
alias hom="ssh_tmux smores@home.mohr.codes"
alias doc="ssh_tmux root@dev.mohr.codes"
alias pfhom="port_forward smores@home.mohr.codes"
alias pfdoc="port_forward root@dev.mohr.codes"

# startup splashes
if status --is-interactive
    # give a splash screen based on whether currently in a tab
    ~/.local/bin/smoresfetch

    # set themes based on time of day
    set_theme

    # set custom prompt
    set fish_greeting
    zoxide init fish | source
    starship init fish | source
end
