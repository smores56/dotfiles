# Environment for every zsh, interactive or not: agents, launchd jobs, and
# editors run `zsh -c`, so nothing they need may live in .zshrc. Nothing here
# touches the network or forks a process.

# ~/.local/bin first so a wrapper (repos, worktrees, dev, the zsh link) wins
# over a system package of the same name; mise shims next, so pinned tools
# resolve without `mise activate`.
typeset -U path
path=("$HOME/.local/bin" "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims" $path)
export PATH

# The personal SDLC registry; the work environment overrides it in env.d.
export SDLC_REPO=smores56/sdlc

export EDITOR=hx
export VISUAL=$EDITOR
export PAGER=less
export LESS=-FRX
export BAT_THEME=ansi

# The employer's flat checkout root, when it exists (see `repos` and the work
# includeIf in ~/.config/git/machine.inc).
[[ -d $HOME/Blitzy ]] && export BLITZY_REPOS_DIR=$HOME/Blitzy

# sops unwraps the passphrase-protected age identity through this wrapper, so
# no plaintext identity is ever on disk.
[[ -x $HOME/.local/bin/sops-age-key ]] && export SOPS_AGE_KEY_CMD=$HOME/.local/bin/sops-age-key

# The machine's one GitHub token, for gh and git's credential helper alike.
_f=${XDG_CONFIG_HOME:-$HOME/.config}/github-token
[[ -r $_f ]] && read -r GH_TOKEN <"$_f" && export GH_TOKEN

# Per-environment additions (the work hook on smoreswork) drop files here.
for _f in "$ZDOTDIR"/env.d/*.zsh(N); do . "$_f"; done
unset _f
