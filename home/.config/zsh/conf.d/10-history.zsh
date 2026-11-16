# Explicit, because macOS /etc/zshrc otherwise sets $ZDOTDIR/.zsh_history and
# 2000 entries. zim's environment module sets the sharing options.
HISTFILE=$HOME/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
