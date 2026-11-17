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
    dot   'mise -C ~/repos/github.com/smores56/dotfiles dot apply'
    boot  'mise -C ~/repos/github.com/smores56/dotfiles bootstrap'
    cr    'repos'
    cw    'worktrees'
    dv    'dev'
    wg    'repos get'
    wn    'worktrees new'
    wp    'worktrees prune'
    wl    'worktrees list'
  )
  local name
  for name in ${(k)abbrs}; do
    abbr add --session --quiet --force -- "$name=${abbrs[$name]}" >/dev/null 2>&1
  done
}
