#!/usr/bin/env bash
# bootstrap.sh: install the user-level package set on a fresh Fedora Atomic
# (COSMIC) install. No sudo: Flatpaks are user installs, mise lives in
# ~/.local/bin, and sdlc is a uv tool. The one host-level install (Tailscale and
# rsync) is printed, not run.
#
# Prerequisites: run install.sh first, so ~/.config/mise/config.toml exists.
# usage: scripts/bootstrap.sh [--skip-flatpaks]
set -euo pipefail

repo=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
skip_flatpaks=false

usage() {
    cat <<'EOF'
usage: scripts/bootstrap.sh [--skip-flatpaks]

  --skip-flatpaks  do not install the user Flatpaks
EOF
}

while [ $# -gt 0 ]; do
    case $1 in
        --skip-flatpaks) skip_flatpaks=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'bootstrap: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

command -v rpm-ostree >/dev/null 2>&1 \
    || printf 'bootstrap: rpm-ostree not found; this script targets Fedora Atomic\n' >&2

# The mise release this file is allowed to fetch, with that release's
# published sha256 for each architecture. A mismatch aborts before unpacking.
MISE_VERSION=v2026.11.8
MISE_SHA_X86_64=d2d5a46f507bba772686e2c8f2316b3a4439dac49a37a30db5c0e7bb077c5431
MISE_SHA_AARCH64=b36da3c4892380325d44dee3678ba618de191254d8a4aed8011ee66b28a6cbd7

# The sdlc CLI comes from the private upstream, pinned by commit: uv resolves
# the repository at that exact revision, so a moved tag cannot change what is
# installed. Bump SDLC_REV deliberately and re-run this script.
SDLC_UPSTREAM=git+ssh://git@github.com/smores56/sdlc
SDLC_REV=6f6dde8caf7c7049fc5bb1009261410fa8f0eb44

log() { printf 'bootstrap: %s\n' "$*"; }
die() { printf 'bootstrap: %s\n' "$*" >&2; exit 1; }

install_flatpaks() {
    local app
    if ! command -v flatpak >/dev/null 2>&1; then
        die "flatpak is not installed; it ships with Fedora Atomic, so this is not an Atomic host"
    fi
    flatpak remote-add --if-not-exists --user flathub \
        https://flathub.org/repo/flathub.flatpakrepo
    while IFS= read -r app; do
        case $app in
            ''|'#'*) continue ;;
        esac
        if flatpak info --user "$app" >/dev/null 2>&1; then
            log "flatpak present: $app"
        else
            log "installing flatpak: $app"
            flatpak install --user -y --noninteractive flathub "$app" \
                || printf 'bootstrap: Flathub install failed for %s; install it by hand\n' "$app" >&2
        fi
    done <"$repo/packages/flatpaks.txt"
}

install_mise() {
    local arch sha asset url work
    if command -v mise >/dev/null 2>&1; then
        log "mise present: $(mise --version 2>/dev/null | head -n 1)"
        return
    fi
    case $(uname -m) in
        x86_64)
            arch=linux-x64
            sha=$MISE_SHA_X86_64 ;;
        aarch64|arm64)
            arch=linux-arm64
            sha=$MISE_SHA_AARCH64 ;;
        *)
            die "unsupported architecture for the pinned mise release: $(uname -m)" ;;
    esac
    asset="mise-${MISE_VERSION}-${arch}.tar.gz"
    url="https://github.com/jdx/mise/releases/download/${MISE_VERSION}/${asset}"
    work=$(mktemp -d) || die "cannot create a temporary directory"
    # shellcheck disable=SC2064 # expand work now
    trap "rm -rf '$work'" EXIT HUP INT TERM
    log "downloading $url"
    curl -fL --proto '=https' --tlsv1.2 -o "$work/$asset" "$url" \
        || die "could not download $url"
    if ! printf '%s  %s\n' "$sha" "$work/$asset" | sha256sum -c - >/dev/null 2>&1; then
        die "$asset does not match the pinned $sha"
    fi
    tar -xzf "$work/$asset" -C "$work" || die "could not extract $asset"
    [ -x "$work/mise/bin/mise" ] || die "$asset does not contain mise/bin/mise"
    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$work/mise/bin/mise" "$HOME/.local/bin/mise"
    log "installed mise $MISE_VERSION at $HOME/.local/bin/mise"
}

# sdlc needs gh, which comes from the mise pin, so it installs after the mise
# step. uv keeps the tool isolated and links `sdlc` into ~/.local/bin.
install_sdlc() {
    local pin="$SDLC_UPSTREAM@$SDLC_REV"
    if ! command -v uv >/dev/null 2>&1; then
        printf 'bootstrap: uv is missing; sdlc was not installed (run: uv tool install %s)\n' "$pin" >&2
        return 1
    fi
    log "installing sdlc at $SDLC_REV"
    if ! uv tool install --force "$pin"; then
        printf 'bootstrap: could not install sdlc; the upstream repo is private, so this needs a GitHub SSH credential\n' >&2
        return 1
    fi
}

log "linking is install.sh's job; this script installs packages"
[ -f "$HOME/.config/mise/config.toml" ] \
    || die "run ./install.sh first: ~/.config/mise/config.toml is missing"

export PATH="$HOME/.local/bin:$PATH"

$skip_flatpaks || install_flatpaks
install_mise

log "installing pinned CLI tools"
MISE_GLOBAL_CONFIG_FILE=$repo/packages/mise.toml mise install
mise reshim
install_sdlc

log "shell integration"
log "  fish activates mise from ~/.config/fish/conf.d/mise.fish"
fish_shim=$HOME/.local/share/mise/shims/fish
if [ -x "$fish_shim" ]; then
    log "  fish shim: $fish_shim"
    log "  optional login shell (needs sudo; the shim survives version bumps):"
    log "    sudo sh -c \"printf '%s\\n' '$fish_shim' >> /etc/shells\""
    log "    chsh -s $fish_shim"
fi

cat <<'EOF'

Host-level services are the only rpm-ostree layer. Run this once, by hand,
because it needs root and a reboot. rsync belongs in the same layer: no
user-level installer provides it and the wallpaper sync needs it.

    sudo rpm-ostree install tailscale rsync
    sudo systemctl reboot

After the reboot:

    sudo systemctl enable --now tailscaled
    sudo tailscale up

Then install Maki: scripts/install-maki.sh
EOF
