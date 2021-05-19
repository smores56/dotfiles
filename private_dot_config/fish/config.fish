# set TERM if it is not set yet
if test -z $TERM; set -xg TERM xterm; end

# set env vars 
set -xg PATH /usr/local/go/bin $HOME/go/bin $HOME/.cargo/bin $HOME/.local/bin /usr/lib/zig $PATH
set -xg EDITOR kak-spawn

# include custom functions
source ~/.config/fish/functions/custom.fish

# set aliases
alias k="kak-spawn"
alias e="exa"
alias a="amp"
alias t="tmux-smart"
alias r="ranger"
alias cm="chezmoi"
alias g="gitui"
alias df="gitui -d ~/.local/share/chezmoi/"
alias st="set-theme"
alias lpk="ssh root@lpk.wiki"
alias hom="ssh-tmux smores@home.mohr.codes"
alias doc="ssh-tmux root@dev.mohr.codes"
alias pfhom="port-forward smores@home.mohr.codes"
alias pfdoc="port-forward root@dev.mohr.codes"

# change directory with ranger using ctrl-O 
bind \co ranger-cd

# startup splashes
if status --is-interactive
    # give a splash screen based on whether currently in a tab
    ~/.local/bin/smoresfetch

    # set themes based on time of day
    set-theme

    # set custom prompt
    set fish_greeting
    zoxide init fish | source
    starship init fish | source
end
