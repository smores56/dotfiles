#!/bin/sh
# Print this machine's mise environment set: macOS is the work laptop, Linux
# with a graphical session or Flatpak is a desktop, other Linux is a server.
# DOTFILES_ENVS overrides the inference.
set -eu

if [ -n "${DOTFILES_ENVS-}" ]; then
    printf '%s\n' "$DOTFILES_ENVS"
    exit 0
fi

# A configured display manager, a live display, or Flatpak marks a desktop.
# The default target does not: headless cloud images ship graphical.target.
graphical() {
    command -v flatpak >/dev/null 2>&1 && return 0
    [ -n "${DISPLAY-}${WAYLAND_DISPLAY-}" ] && return 0
    command -v systemctl >/dev/null 2>&1 \
        && systemctl is-enabled --quiet display-manager.service 2>/dev/null
}

case $(uname -s) in
    Darwin)
        printf 'desktop,work\n'
        ;;
    Linux)
        if graphical; then
            printf 'desktop,identity\n'
        else
            printf 'identity\n'
        fi
        ;;
    *)
        printf 'detect-envs: unsupported system %s\n' "$(uname -s)" >&2
        exit 1
        ;;
esac
