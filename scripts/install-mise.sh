#!/bin/sh
# install-mise.sh: set up a machine that has no mise yet. Installs the pinned
# mise release into ~/.local/bin after checking its published sha256, then
# hands over to `mise bootstrap` from this repository at a pinned commit.
#
# usage: install-mise.sh <40-hex commit> <env set> [extra bootstrap args...]
#   env sets: identity (smortress), desktop,identity (smorespro), desktop,work (smoreswork)
#
# Re-running with a newer commit moves the checkout there (`--update`). The
# login shell is always skipped here (so extra args cannot use `--only`); it is
# a separate, interactive step afterwards because chsh prompts for a password:
#   mise -C ~/repos/github.com/smores56/dotfiles bootstrap --only user
set -eu

MISE_VERSION=v2026.11.9
MISE_SHA_LINUX_X64=23ba592fcbc61f057e2b82c1eafd085832712ba0c759b714ca16cd06babca378
MISE_SHA_LINUX_ARM64=cf2900bfb4279f8d8f8a19d5c27bf1bde826b3e742182f3f67511c588498c786
MISE_SHA_MACOS_ARM64=e4509f159e0492e89065edcf52f2918e2751e3574620586058468ba0563aed59
REPO_URL=https://github.com/smores56/dotfiles.git
CHECKOUT=$HOME/repos/github.com/smores56/dotfiles

die() { printf 'install-mise: %s\n' "$*" >&2; exit 1; }

[ $# -ge 2 ] || die "usage: install-mise.sh <commit> <env set> [bootstrap args...]"
ref=$1 envs=$2
shift 2
printf '%s' "$ref" | grep -Eqx '[0-9a-f]{40}' || die "the ref must be a full commit sha, not a branch: $ref"

case "$(uname -s)/$(uname -m)" in
    Linux/x86_64) platform=linux-x64 sha=$MISE_SHA_LINUX_X64 ;;
    Linux/aarch64|Linux/arm64) platform=linux-arm64 sha=$MISE_SHA_LINUX_ARM64 ;;
    Darwin/arm64) platform=macos-arm64 sha=$MISE_SHA_MACOS_ARM64 ;;
    *) die "no pinned mise release for $(uname -s)/$(uname -m)" ;;
esac

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

mise=$HOME/.local/bin/mise
if [ -x "$mise" ] && "$mise" --version 2>/dev/null | grep -q "^${MISE_VERSION#v} "; then
    printf 'install-mise: mise %s present\n' "$MISE_VERSION"
else
    work=$(mktemp -d) || die "cannot create a temporary directory"
    trap 'rm -rf "$work"' EXIT
    trap 'exit 1' HUP INT TERM
    asset=mise-$MISE_VERSION-$platform.tar.gz
    curl -fsSL --proto '=https' --tlsv1.2 -o "$work/$asset" \
        "https://github.com/jdx/mise/releases/download/$MISE_VERSION/$asset" || die "could not download $asset"
    [ "$(sha256 "$work/$asset")" = "$sha" ] || die "$asset does not match the pinned sha256 $sha"
    tar -xzf "$work/$asset" -C "$work"
    mkdir -p "$HOME/.local/bin"
    install -m 0755 "$work/mise/bin/mise" "$mise"
    # exec below replaces this shell before an EXIT trap could fire.
    rm -rf "$work"
    printf 'install-mise: installed mise %s\n' "$MISE_VERSION"
fi

# `--config-dir` links ~/.config/mise to global/ and refuses when a real
# directory is there, which is what the retired install.sh left behind (a
# config.toml symlink into packages/). Keep it aside rather than delete it.
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/mise
if [ -e "$config_dir" ] && [ ! -L "$config_dir" ]; then
    aside=$config_dir.pre-bootstrap.$(date +%Y%m%d%H%M%S)
    mv "$config_dir" "$aside"
    printf 'install-mise: moved the old %s to %s\n' "$config_dir" "$aside"
fi

exec "$mise" bootstrap \
    --from "$REPO_URL?ref=$ref" --from-dir "$CHECKOUT" --config-dir global \
    -E "$envs" --prompt-vars --save-env --skip user --update --yes "$@"
