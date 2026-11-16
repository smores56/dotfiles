# Tool integrations, each guarded so a machine before `mise install` (or a
# container) still gets a working shell.
(( $+commands[zoxide] )) && eval "$(zoxide init zsh --cmd c)"
# atuin after zim so its Ctrl-R and up-arrow bindings win over zim's input
# module; it prepends itself to the suggestion strategy, so reset that after.
(( $+commands[atuin] )) && eval "$(atuin init zsh)"
ZSH_AUTOSUGGEST_STRATEGY=(abbreviations history)
