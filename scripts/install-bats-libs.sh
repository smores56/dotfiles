#!/bin/sh
# Install the bats assertion libraries the suites load. bats searches
# $BATS_LIB_PATH, whose default is /usr/lib/bats, so tests/helpers.bash points
# it here instead: no root, and one path on Linux and macOS.
#
# The digest is the pin, not the tag: a mismatched download is discarded and
# the installed copy is left alone.
set -eu

log() { printf 'bats-libs: %s\n' "$*" >&2; }

dest=${XDG_DATA_HOME:-$HOME/.local/share}/bats

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
    work=$(mktemp -d) || return 1
    trap 'rm -rf "$work"' EXIT HUP INT TERM
    url=https://github.com/bats-core/$name/archive/refs/tags/v$version.tar.gz
    log "installing $name $version"
    if ! curl -fsSL --retry 3 -o "$work/lib.tar.gz" "$url"; then
        log "could not download $name $version"
        return 1
    fi
    if [ "$(file_digest "$work/lib.tar.gz")" != "$digest" ]; then
        log "$name $version checksum mismatch; leaving the installed copy alone"
        return 1
    fi
    tar -xzf "$work/lib.tar.gz" -C "$work" || return 1
    rm -rf "${dest:?}/$name"
    mkdir -p "$dest"
    mv "$work/$name-$version" "$dest/$name"
    printf '%s\n' "$version" >"$dest/$name/.version"
}

install_lib bats-support 0.3.0 7815237aafeb42ddcc1b8c698fc5808026d33317d8701d5ec2396e9634e2918f \
    || log "bats-support missing; every suite fails to load"
install_lib bats-assert 2.2.4 e305df20c4c36cba4570e10f1cd824efb1ae71d88b5ef474550781ebee04192f \
    || log "bats-assert missing; every suite fails to load"
