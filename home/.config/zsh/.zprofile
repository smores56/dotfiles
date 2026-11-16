# Login shells only. macOS /etc/zprofile runs path_helper after .zshenv, which
# moves the system directories back in front; restore the .zshenv order.
path=("$HOME/.local/bin" "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims" $path)
