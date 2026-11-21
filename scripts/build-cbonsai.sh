#!/bin/sh
# Builds the vendored cbonsai into ~/.local/bin. Runs as the `cbonsai` task, so
# mise has already put its task-scoped tools (zig and ncurses headers) on PATH.
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
source=$root/vendor/cbonsai/cbonsai.c
destdir=${HOME}/.local/bin
version=1.4.2

log() { printf 'cbonsai-build: %s\n' "$*" >&2; }
die() { log "$*"; exit 1; }

command -v zig >/dev/null 2>&1 || die "zig is not on PATH; run this through mise"
command -v ncursesw6-config >/dev/null 2>&1 || die "ncurses headers are not on PATH; run this through mise"

# The conda ncurses package installs its config script into $prefix/.mise-bins.
prefix=$(dirname -- "$(dirname -- "$(command -v ncursesw6-config)")")

mkdir -p "$destdir"
tmp=$(mktemp "$destdir/.cbonsai.XXXXXX")
trap 'rm -f "$tmp"' EXIT HUP INT TERM

flags="-O2 -Wall -Wextra -Wshadow -Wpointer-arith -Wcast-qual -pedantic -D_GNU_SOURCE -DNCURSES_WIDECHAR"
build() {
    # shellcheck disable=SC2086 # flags is a deliberate word list
    zig cc $flags \
        -I"$prefix/include/ncursesw" -I"$prefix/include" \
        "$source" "$@" -o "$tmp"
}

case $(uname -s) in
Linux)
    # Link the distro's sonames, not conda's: conda's libncursesw needs
    # libtinfow, which Fedora lacks, and its .pc files add an rpath into the
    # mise store. The headers are the only build-time conda input.
    find_libdir() {
        if command -v ldconfig >/dev/null 2>&1; then
            path=$(ldconfig -p 2>/dev/null |
                awk '$1 == "libncursesw.so.6" && tolower($0) ~ /x86-64|aarch64/ { print $NF; exit }')
            [ -n "$path" ] && { dirname -- "$path"; return 0; }
        fi
        for dir in /usr/lib64 /usr/lib/x86_64-linux-gnu /usr/lib/aarch64-linux-gnu /lib64 /usr/lib; do
            [ -e "$dir/libncursesw.so.6" ] && { printf '%s\n' "$dir"; return 0; }
        done
        return 1
    }
    libdir=$(find_libdir) || die "libncursesw.so.6 is not installed"
    build -L"$libdir" -l:libncursesw.so.6 -l:libpanelw.so.6 -l:libtinfo.so.6
    mise_data=${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}
    if ldd "$tmp" | grep -qF "$mise_data"; then
        die "the binary resolves a library from the mise store; the system sonames were not used"
    fi
    ;;
Darwin)
    # macOS has no libncursesw/libtinfo sonames to substitute, so the binary
    # links the pinned conda dylibs and carries an rpath to them. Bootstrap
    # reinstalls that tool and rebuilds, so only a prune without a rebuild breaks it.
    build -L"$prefix/lib" -lncursesw -lpanelw -ltinfow -Wl,-rpath,"$prefix/lib"
    ;;
*)
    die "unsupported platform: $(uname -s)"
    ;;
esac

TERM=xterm-256color "$tmp" -p -L 4 >/dev/null 2>&1 || die "the built binary does not render"
chmod 0755 "$tmp"
mv -f "$tmp" "$destdir/cbonsai"
trap - EXIT HUP INT TERM
log "installed $destdir/cbonsai ($version)"
