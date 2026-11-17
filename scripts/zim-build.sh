#!/bin/sh
# Installs the pinned zimfw.zsh and builds init.zsh from the modules that
# [bootstrap.repos] cloned. The only network access is the one checksummed
# download; a shell start never fetches anything.
set -eu

version=v1.21.0
sha256=8f631937bc6afdfdf26f91a8080dad86e84051f92bb1d91db8004dd1c3383cbd
zim_home=${XDG_CACHE_HOME:-$HOME/.cache}/zim
zdotdir=${ZDOTDIR:-${XDG_CONFIG_HOME:-$HOME/.config}/zsh}

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

# Without the deployed .zimrc there is nothing to build, and zimfw would
# write its own default .zimrc into whatever ZDOTDIR holds.
if [ ! -f "$zdotdir/.zimrc" ]; then
    echo "zim-build: $zdotdir/.zimrc is not deployed yet; skipping"
    exit 0
fi

mkdir -p "$zim_home"
if [ ! -f "$zim_home/zimfw.zsh" ] || [ "$(sha256_of "$zim_home/zimfw.zsh")" != "$sha256" ]; then
    tmp=$zim_home/zimfw.zsh.download
    curl -fsSL --proto '=https' --tlsv1.2 -o "$tmp" \
        "https://github.com/zimfw/zimfw/releases/download/$version/zimfw.zsh"
    [ "$(sha256_of "$tmp")" = "$sha256" ] || { rm -f "$tmp"; echo "zim-build: zimfw.zsh does not match $sha256" >&2; exit 1; }
    mv "$tmp" "$zim_home/zimfw.zsh"
fi
ZIM_HOME=$zim_home ZDOTDIR=$zdotdir zsh "$zim_home/zimfw.zsh" build -q

# zimfw compiles each module into .zwc files beside its sources and has no
# switch to stop that; excluding them locally keeps the pinned checkouts clean
# for `mise bootstrap`'s dirty-repo check without losing the faster startup.
plugins=${XDG_DATA_HOME:-$HOME/.local/share}/zsh-plugins
for repo in "$plugins"/*/; do
    exclude=$(git -C "$repo" rev-parse --git-path info/exclude 2>/dev/null) || continue
    case $exclude in /*) ;; *) exclude=$repo$exclude ;; esac
    mkdir -p "$(dirname "$exclude")"
    grep -qxF '*.zwc' "$exclude" 2>/dev/null || printf '*.zwc\n*.zwc.old\n' >>"$exclude"
done
