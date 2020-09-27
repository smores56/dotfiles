# set basic variables
export PATH=/usr/local/go/bin:$HOME/go/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/lib/zig:$HOME/.local/share/share/ponyup/bin:$PATH
export EDITOR=vim

# load nvm
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 

# set aliases
alias r="ranger"
alias doc="ssh root@167.172.140.191"
alias port_forward_hostwinds="ssh -fNR 80:127.0.0.1:3000 root@dev.mohr.codes"
alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

# define functions
erg() {
    if [ -z "$TMUX" ]; then
        ssh sam@erglabs.org -t tmux new-session -A -s main
    else
        echo "$(tput setaf 1)Don't SSH into tmux from tmux!$(tput sgr0)"
    fi
}

# startup splashes
if [ -z "$TMUX" ]; then
    echo ""
    command -v figlet &>/dev/null && figlet -w 45 -c -d ~/.figlet/fonts/ -f big "S'mores"
    [ -d "$HOME/.pfetch" ] && sh "$HOME/.pfetch/pfetch"
else
    command -v figlet &>/dev/null && figlet -w 32 -c -d ~/.figlet/fonts/ -f rounded "S'mux"
fi

# better cd
command -v zoxide &>/dev/null && eval "$(zoxide init bash)"

# custom prompt
command -v starship &>/dev/null && eval "$(starship init bash)"
