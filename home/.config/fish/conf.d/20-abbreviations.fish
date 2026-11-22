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
abbr -a s 'sdlc pick'
abbr -a sv screensavers
# pull.rebase is on, so --no-rebase keeps this a fast-forward or nothing. The
# status guard catches bootstrap exiting 0 with dotfiles left unapplied.
abbr -a d 'git -C ~/.dotfiles pull --ff-only --no-rebase --autostash && mise -C ~/.dotfiles bootstrap --prune-dotfiles && begin; mise -C ~/.dotfiles dot status --missing --json >/dev/null; or mise -C ~/.dotfiles dot status --missing; end'
abbr -a gw git worktree
abbr -a sm ssh smortress -t fish
abbr -a sn ssh -t root@smoresnet bash -lc fish
# fish's own clipboard functions: copy also sends OSC 52, so it works over SSH
# and through zellij; paste reads pbpaste or wl-paste locally.
abbr -a copy fish_clipboard_copy
abbr -a paste fish_clipboard_paste

# Pickers. Cancelling fzf prints nothing, so read fails and nothing runs.
abbr -a ef 'fd -t f | fzf | read f; and hx $f'
abbr -a et 'rg -n . | fzf -d : --nth 3.. | string replace -r \'^([^:]+:\d+):.*\' \'$1\' | read f; and hx $f'
abbr -a w 'git worktree list | string match -v \'*(bare)\' | fzf | string split -f1 \' \' | read f; and c $f'
