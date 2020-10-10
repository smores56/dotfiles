# set basic variables
export PATH=/usr/local/go/bin:$HOME/go/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/lib/zig:$HOME/.local/share/share/ponyup/bin:$PATH
export EDITOR=kak
export NNN_FIFO=/tmp/nnn.fifo
export NNN_PLUG="i:preview-tui;t:treeview"
export BAT_THEME=gruvbox

# load nvm
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# set aliases
alias r="ranger"
alias lg="lazygit"
alias hom="ssh smores@home.mohr.codes"
alias pfhom="ssh -gfNR 80:127.0.0.1:3000 root@dev.mohr.codes"
alias doc="ssh root@dev.mohr.codes"
alias pfdoc="ssh -gfNR 80:127.0.0.1:3000 root@dev.mohr.codes"
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

# switch escape and caps lock
command -v setxkbmap &>/dev/null && setxkbmap -option caps:swapescape

# better cd
command -v zoxide &>/dev/null && eval "$(zoxide init bash)"

# custom prompt
command -v starship &>/dev/null && eval "$(starship init bash)"
