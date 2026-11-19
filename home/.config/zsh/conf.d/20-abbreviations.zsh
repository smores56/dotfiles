# Shared abbreviations, loaded per session so zsh-abbr never rewrites a file
# this repository owns. Add a machine-only one with `abbr add`; promote it by
# moving the line here.
(( $+functions[abbr] )) || return 0
() {
  local -A abbrs=(
    e     'hx'
    l     'eza --icons --group-directories-first -lh'
    la    'eza --icons --group-directories-first -lah'
    f     'yazi'
    b     'bat'
    g     'lazygit'
    m     'mkdir -p'
    t     'zellij a -c main'
    gp    'gh pr create'
    a     'maki'
    s     'sdlc ui'
    # Two applies: the first after the checkout moves (or a dotfile group's
    # source path changes) prunes the old links without recreating them, and
    # the second converges. See docs/manual-steps.md.
    dot   'git -C ~/.dotfiles pull --ff-only --no-rebase --autostash && mise -C ~/.dotfiles dot apply --yes && mise -C ~/.dotfiles dot apply --yes'
    boot  'mise -C ~/.dotfiles bootstrap'
    dv    'dev'
    gq    'ghq'
    gw    'git worktree'
    gc    '~/.dotfiles/scripts/clone-checkout.sh'
  )
  # zsh-abbr forks `rm` per add to release a queue lock that session adds
  # never take; its file-loading flag skips that (~3ms per abbreviation).
  local name ABBR_LOADING_USER_ABBREVIATIONS=1
  for name in ${(k)abbrs}; do
    abbr add --session --quiet --force -- "$name=${abbrs[$name]}" >/dev/null 2>&1
  done
}
