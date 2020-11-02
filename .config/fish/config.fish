# set env vars 
set -x PATH /usr/local/go/bin $HOME/go/bin $HOME/.cargo/bin $HOME/.local/bin /usr/lib/zig $HOME/.local/share/ponyup/bin /usr/local/lib/swift/usr/bin/ $PATH
set -x EDITOR kak
set -x BAT_THEME gruvbox

# include custom functions
source ~/.config/fish/functions/custom.fish

# set aliases
alias k="kak"
alias kf="kak (fzf-tmux)"
alias r="ranger"
alias lg="lazygit"
alias df="dotfiles"
alias t="tmux a 2>/dev/null; or tmux new -s main"
alias erg="ssh_tmux sam@erglabs.org"
alias hom="ssh_tmux smores@home.mohr.codes"
alias doc="ssh_tmux root@dev.mohr.codes"
alias pfhom="port_forward smores@home.mohr.codes"
alias pfdoc="port_forward root@dev.mohr.codes"

# startup splashes
if status --is-interactive
    if test "$TMUX" = ""
        echo ""
        if type -q figlet
            figlet -w 45 -c -d ~/.figlet/fonts/ -f big "S'mores"
        end
        sh ~/.pfetch/pfetch
    else
        if type -q figlet
            figlet -w 32 -c -d ~/.figlet/fonts/ -f rounded "S'mux"
        end
    end
end

# set custom prompt
set fish_greeting
zoxide init fish | source
starship init fish | source

# install nvm
fundle plugin 'FabioAntunes/fish-nvm'
fundle plugin 'edc/bass'
fundle init
