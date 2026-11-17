# After every PATH change, so mise-managed tools win on PATH over anything
# earlier files (or the work hook's pyenv and nvm) added.
(( $+commands[mise] )) && eval "$(mise activate zsh)"
