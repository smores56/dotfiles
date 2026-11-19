# Login zsh only. macOS /etc/zprofile runs path_helper after ~/.zshenv, which
# moves the system directories back in front; the shared file restores the order.
emulate sh -c '. "${XDG_CONFIG_HOME:-$HOME/.config}/shell/env.sh"'
