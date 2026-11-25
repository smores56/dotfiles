#!/bin/sh
# Install the bats assertion libraries the suites load. bats searches
# $BATS_LIB_PATH, whose default is /usr/lib/bats, so tests/helpers.bash points
# it here instead: no root, and one path on Linux and macOS.
#
# The digest is the pin, not the tag: a mismatched download is discarded and
# the installed copy is left alone. The swap in happens only once a verified
# tree is complete, so an interrupted install never leaves a half-library.
set -eu

log() { printf 'bats-libs: %s\n' "$*" >&2; }

dest=${XDG_DATA_HOME:-$HOME/.local/share}/bats
case $dest in
    /*) ;;
    *) log "XDG_DATA_HOME must be absolute, got '$dest'"; exit 1 ;;
esac

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

file_digest() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

install_lib() {  # install_lib <name> <version> <sha256>
    name=$1 version=$2 digest=$3
    if [ -f "$dest/$name/load.bash" ] && [ "$(cat "$dest/$name/.version" 2>/dev/null)" = "$version" ]; then
        return 0
    fi
    url=https://github.com/bats-core/$name/archive/refs/tags/v$version.tar.gz
    log "installing $name $version"
    if ! curl -fsSL --retry 3 -o "$work/$name.tar.gz" "$url"; then
        log "could not download $name $version"
        return 1
    fi
    if [ "$(file_digest "$work/$name.tar.gz")" != "$digest" ]; then
        log "$name $version checksum mismatch; leaving the installed copy alone"
        return 1
    fi
    mkdir -p "$work/$name" "$dest" || return 1
    tar -xzf "$work/$name.tar.gz" -C "$work/$name" || return 1
    rm -rf "${dest:?}/$name.new"
    mv "$work/$name/$name-$version" "$dest/$name.new" || return 1
    printf '%s\n' "$version" >"$dest/$name.new/.version"
    rm -rf "${dest:?}/$name"
    mv "$dest/$name.new" "$dest/$name"
}

failed=0
install_lib bats-support 0.3.0 7815237aafeb42ddcc1b8c698fc5808026d33317d8701d5ec2396e9634e2918f || failed=1
install_lib bats-assert 2.2.4 e305df20c4c36cba4570e10f1cd824efb1ae71d88b5ef474550781ebee04192f || failed=1
# Every suite fails to load without both, so a partial install must be loud.
exit "$failed"
