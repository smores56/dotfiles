#!/bin/sh
# Remove the uv-managed sdlc shim left by the retired install before the
# identity dotfiles link the in-repo CLI. Only the known uv-tool symlink is
# removed; anything else is left alone for the operator to resolve.
set -eu

target=$HOME/.local/bin/sdlc
[ -L "$target" ] || exit 0

case $(readlink "$target") in
    "$HOME/.local/share/uv/tools/smores-sdlc/"*)
        rm -f "$target"
        printf 'retire-uv-sdlc: removed the uv shim %s\n' "$target"
        ;;
esac
