# The employer's setup tool owns ~/.zshrc (pyenv, nvm, gcloud, 1Password,
# env functions). With ZDOTDIR set zsh never reads it, so source it here:
# after compinit (its gcloud and nvm blocks load completions) and before
# 99-mise.zsh, so mise's tools win over pyenv and nvm on PATH.
[[ -r $HOME/.zshrc ]] && source "$HOME/.zshrc"

# On the work laptop the agent is Claude Code, not maki.
(( $+functions[abbr] )) && abbr add --session --quiet --force -- 'a=claude'

# kitty stays installed beside WezTerm until it is retired.
if [[ -n ${KITTY_INSTALLATION_DIR-} ]]; then
  export KITTY_SHELL_INTEGRATION=no-rc
  autoload -Uz -- "$KITTY_INSTALLATION_DIR"/shell-integration/zsh/kitty-integration
  kitty-integration
  unfunction kitty-integration
fi
