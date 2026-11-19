# smoreswork. Work checkouts are flat hand clones in ~/Blitzy, with worktrees
# under each clone's .worktrees/.
status is-interactive; or return

abbr -a a claude
abbr -a r 'path dirname ~/Blitzy/*/.git ~/Blitzy/*/.worktrees/*/.git | fzf | read f; and c $f'
