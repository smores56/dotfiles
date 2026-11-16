# Login shells only. macOS /etc/zprofile runs path_helper after .zshenv, which
# moves the system directories back in front: re-run the environment hooks
# (the work hook re-sources the Nix profile), then restore the .zshenv order.
for _f in "$ZDOTDIR"/env.d/*.zsh(N); do . "$_f"; done
unset _f
path=("$HOME/.local/bin" "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims" $path)
