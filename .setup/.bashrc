export PATH=/usr/local/go/bin:$HOME/.cargo/bin:$HOME/.local/bin/:/usr/lib/zig/0.6.0/:$PATH
export EDITOR=vim
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

alias port_forward_hostwinds="ssh -fNR 80:127.0.0.1:3000 root@dev.mohr.codes"
alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

# switch escape and caps lock
command -v setxkbmap &>/dev/null && setxkbmap -option caps:swapescape

# startup data
if [ -z "$TMUX" ]; then
    echo ""
    command -v figlet &>/dev/null && figlet -c -w 100 -d ~/.figlet/fonts/ -f colossal "S'mores"
    command -v neofetch &>/dev/null && neofetch --music-player cmus
else
    command -v figlet &>/dev/null && figlet -f small "S'mores"
fi

# custom prompt
command -v starship &>/dev/null && eval "$(starship init bash)"
