# Short aliases for tools that exist on both Fedora Atomic and macOS. No
# package-manager aliases: the package manager differs per OS and is invoked
# rarely enough that typing it is cheaper than remembering two sets of aliases.
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
    abbr -a -- cm chezmoi
    abbr -a -- ca 'chezmoi apply'
    abbr -a -- cdiff 'chezmoi diff'
    abbr -a -- cr repos
    abbr -a -- cw worktrees
    abbr -a -- dv dev
    abbr -a -- r 'pick repos c'
    abbr -a -- w 'pick worktrees c'
    abbr -a -- wg 'repos get'
    abbr -a -- wn 'worktrees new'
    abbr -a -- wp 'worktrees prune'
    abbr -a -- wl 'worktrees list'
end
