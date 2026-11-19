# Abbreviations for every machine; the lane files later in conf.d add to them
# or replace one.
status is-interactive; or return

abbr -a e hx
abbr -a f yazi
abbr -a g lazygit
abbr -a l eza --icons --group-directories-first -lh
abbr -a m mkdir -p
abbr -a t zellij a -c main
abbr -a a maki
abbr -a s sdlc
# pull.rebase is on, so --no-rebase keeps this a fast-forward or nothing.
abbr -a d 'git -C ~/.dotfiles pull --ff-only --no-rebase --autostash && mise -C ~/.dotfiles bootstrap'
abbr -a gw git worktree
abbr -a copy cb copy
abbr -a paste cb paste

# Pickers. Cancelling fzf prints nothing, so read fails and nothing runs.
abbr -a ef 'fd -t f | fzf | read f; and hx $f'
abbr -a et 'rg -n . | fzf -d : --nth 3.. | string replace -r \'^([^:]+:\d+):.*\' \'$1\' | read f; and hx $f'
abbr -a w 'git worktree list | string match -v \'*(bare)\' | fzf | string split -f1 \' \' | read f; and c $f'
