# zsh and bash source this file and fish imports what it exports. POSIX sh, and
# nothing here forks or touches the network: every shell pays for it.

# A ZDOTDIR inherited from a session older than this file would make every
# later zsh skip ~/.zshenv, and with it this environment.
unset ZDOTDIR

# Move an entry to the front of PATH. Login zsh on macOS reorders PATH with
# path_helper after ~/.zshenv, so ~/.zprofile sources this file again and the
# entries must move, not merely be present.
_env_front() {
    _env_rest=
    _env_ifs=$IFS
    IFS=:
    for _env_p in $PATH; do
        [ "$_env_p" = "$1" ] || _env_rest=${_env_rest:+$_env_rest:}$_env_p
    done
    IFS=$_env_ifs
    PATH=$1${_env_rest:+:$_env_rest}
}

# ~/.local/bin first so a wrapper (maki, sdlc) wins over a tool of the same
# name; mise shims next, which is how every shell resolves the pinned tools.
_env_front "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims"
_env_front "$HOME/.local/bin"
export PATH

export EDITOR=hx
export VISUAL=hx
export PAGER=bat
export BAT_THEME=ansi
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

export SDLC_REPO=smores56/sdlc

# The employer's flat checkout root, when it exists (see ~/.claude/work.md).
[ -d "$HOME/Blitzy" ] && export BLITZY_REPOS_DIR="$HOME/Blitzy"

# sops unwraps the passphrase-protected age identity through this wrapper, so
# no plaintext identity is ever on disk.
[ -x "$HOME/.local/bin/sops-age-key" ] && export SOPS_AGE_KEY_CMD="$HOME/.local/bin/sops-age-key"

_env_f=${XDG_CONFIG_HOME:-$HOME/.config}/gh/token
# read fails at a missing final newline, but the token is still read.
[ -r "$_env_f" ] && { read -r GH_TOKEN <"$_env_f" || [ -n "$GH_TOKEN" ]; } && export GH_TOKEN

for _env_f in "${XDG_CONFIG_HOME:-$HOME/.config}"/shell/env.d/*.sh; do
    # shellcheck source=/dev/null
    [ -r "$_env_f" ] && . "$_env_f"
done

unset _env_f _env_p _env_rest _env_ifs
unset -f _env_front
