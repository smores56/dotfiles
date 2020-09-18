# set basic variables
export PATH=/usr/local/go/bin:$HOME/.cargo/bin:$HOME/.local/bin/:/usr/lib/zig/0.6.0/:$PATH
export EDITOR=vim

# load nvm
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" 

# set aliases
alias erg="ssh sam@erglabs.org"
alias hwd="ssh root@dev.mohr.codes"
alias port_forward_hostwinds="ssh -fNR 80:127.0.0.1:3000 root@dev.mohr.codes"
alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

# switch escape and caps lock
command -v setxkbmap &>/dev/null && setxkbmap -option caps:swapescape

# startup splashes
if [ -z "$TMUX" ]; then
    echo ""
    command -v figlet &>/dev/null && figlet -w 45 -c -d ~/.figlet/fonts/ -f big "S'mores"
    [ -d "$HOME/.pfetch" ] && sh "$HOME/.pfetch/pfetch"
else
    command -v figlet &>/dev/null && figlet -d ~/.figlet/fonts/ -f rounded "S'mux"
fi

# better cd
command -v zoxide &>/dev/null && eval "$(zoxide init bash)"

# custom prompt
command -v starship &>/dev/null && eval "$(starship init bash)"
