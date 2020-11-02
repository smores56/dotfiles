# set env vars 
set -x PATH /usr/local/go/bin $HOME/go/bin $HOME/.cargo/bin $HOME/.local/bin /usr/lib/zig $HOME/.local/share/share/ponyup/bin $PATH
set -x EDITOR kak
set -x BAT_THEME gruvbox

# set aliases
alias k="kak"
alias kf="kak (fzf-tmux)"
alias r="ranger"
alias lg="lazygit"
alias df="dotfiles"
alias t="tmux a 2>/dev/null || tmux new -s main"
alias erg="ssh_tmux sam@erglabs.org"
alias hom="ssh_tmux smores@home.mohr.codes"
alias doc="ssh_tmux root@dev.mohr.codes"
alias pfhom="port_forward smores@home.mohr.codes"
alias pfdoc="port_forward root@dev.mohr.codes"

# define functions
function error --description "Print error to stderr"
    echo (tput setaf 1)"error: $argv"(tput sgr0) 1>&2
end

function dotfiles --description "Manage my dotfiles"
    git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME $argv
end

function ssh_tmux --description "SSH into a TMUX session"
    if test (count $argv) -gt 0
        set SshLocation $argv[1]
    else
        error "Must specify where to port forward"
        return 1
    end

    if test "$TMUX" = ""
        ssh "$SshLocation" -t "tmux a 2>/dev/null || tmux new -s main; exit"
    else
        error "Don't SSH into tmux from tmux!"
        return 1
    end
end

function port_forward --description "Port forward through SSH server"
    if test (count $argv) -gt 0
        set SshLocation $argv[1]
    else
        error "Must specify where to port forward"
        return 1
    end

    set InternalPort ( if test (count $argv) -gt 1; echo $argv[2]; else; echo 3000; end )
    set ExternalPort ( if test (count $argv) -gt 2; echo $argv[3]; else; echo 80; end )

    ssh -gfNR "$ExternalPort:127.0.0.1:$InternalPort" "$SshLocation"
end

# startup splashes
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

# set custom prompt
set fish_greeting
zoxide init fish | source
starship init fish | source

# install nvm
fundle plugin 'FabioAntunes/fish-nvm'
fundle plugin 'edc/bass'
fundle init
