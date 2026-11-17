#!/bin/sh
# install-mise.sh: set up a machine that has no mise yet. Runs the official
# installer at the pinned mise version, then hands over to `mise bootstrap`
# from this repository at a pinned commit. The official installer verifies the
# release checksum itself and needs tar plus gzip (or zstd), which every target
# base image ships.
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
REPO_URL=https://github.com/smores56/dotfiles.git
CHECKOUT=$HOME/repos/github.com/smores56/dotfiles

die() { printf 'install-mise: %s\n' "$*" >&2; exit 1; }

[ $# -ge 2 ] || die "usage: install-mise.sh <commit> <env set> [bootstrap args...]"
ref=$1 envs=$2
shift 2
printf '%s' "$ref" | grep -Eqx '[0-9a-f]{40}' || die "the ref must be a full commit sha, not a branch: $ref"

mise=$HOME/.local/bin/mise
if [ -x "$mise" ] && "$mise" --version 2>/dev/null | grep -q "^${MISE_VERSION#v} "; then
    printf 'install-mise: mise %s present\n' "$MISE_VERSION"
else
    # The installer script checks the downloaded release against its own
    # checksum; MISE_VERSION keeps it on the version this repository expects.
    curl -fsSL --proto '=https' --tlsv1.2 https://mise.run \
        | MISE_VERSION=$MISE_VERSION MISE_INSTALL_HELP=0 sh \
        || die "the official mise installer failed"
    [ -x "$mise" ] || die "the official installer did not write $mise"
    "$mise" --version | grep -q "^${MISE_VERSION#v} " \
        || die "mise is not $MISE_VERSION after the official install"
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
