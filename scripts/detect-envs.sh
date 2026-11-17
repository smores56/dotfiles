#!/bin/sh
# Print the mise environment set for this machine. The wrapper uses it only on
# the first bootstrap; --save-env then records the set in miserc.local.toml.
#
# The fleet rule: macOS is the work laptop; a Linux machine with Flatpak, a
# graphical default target, or a display is a desktop; other Linux is a server.
# DOTFILES_ENVS overrides the inference, for a personal Mac or an unusual host.
set -eu

if [ -n "${DOTFILES_ENVS-}" ]; then
    printf '%s\n' "$DOTFILES_ENVS"
    exit 0
fi

case $(uname -s) in
    Darwin)
        printf 'desktop,work\n'
        ;;
    Linux)
        if command -v flatpak >/dev/null 2>&1 \
                || [ "$(systemctl get-default 2>/dev/null || true)" = graphical.target ] \
                || [ -n "${DISPLAY-}${WAYLAND_DISPLAY-}" ]; then
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
