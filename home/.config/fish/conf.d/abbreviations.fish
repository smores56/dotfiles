# Short aliases for the tools this desktop installs. Nothing here runs a
# package manager: the sources are Flatpak, mise, and one rpm-ostree layer.
if status is-interactive
    abbr -a -- e hx
    abbr -a -- ef 'pick files hx'
    abbr -a -- et 'pick text hx'
    abbr -a -- l 'eza --icons --group-directories-first -lh'
    abbr -a -- la 'eza --icons --group-directories-first -lah'
    abbr -a -- f yazi
    abbr -a -- b bat
    abbr -a -- g lazygit
    abbr -a -- m 'mkdir -p'
    abbr -a -- t 'zellij a -c main'
    abbr -a -- gp 'gh pr create'
    abbr -a -- a maki
    abbr -a -- ms 'pick maki-sessions maki-session-resume'
    abbr -a -- dot '~/repos/github.com/smores56/dotfiles/install.sh'
    abbr -a -- boot '~/repos/github.com/smores56/dotfiles/scripts/bootstrap.sh'
    abbr -a -- cr repos
    abbr -a -- cw worktrees
    abbr -a -- dv dev
    abbr -a -- r 'pick repos cd'
    abbr -a -- w 'pick worktrees cd'
    abbr -a -- wg 'repos get'
    abbr -a -- wn 'worktrees new'
    abbr -a -- wp 'worktrees prune'
    abbr -a -- wl 'worktrees list'
end
