#!/bin/sh
# install-mise.sh: set up a machine that has no mise yet. Runs the official
# installer for the latest stable mise, then applies this repository's latest
# main with `mise bootstrap`. The machine set is inferred by detect-envs.sh;
# override it with DOTFILES_ENVS when the inference is wrong.
#
# usage: install-mise.sh [extra bootstrap args...]
#   DOTFILES_ENVS=desktop,identity scripts/install-mise.sh
#
# Re-running updates the checkout to the current main (`--update`). The login
# shell is always skipped here (so extra args cannot use `--only`); it is a
# separate, interactive step afterwards because chsh prompts for a password:
#   mise -C ~/repos/github.com/smores56/dotfiles bootstrap --only user
set -eu

REPO_URL=https://github.com/smores56/dotfiles.git
CHECKOUT=$HOME/repos/github.com/smores56/dotfiles

die() { printf 'install-mise: %s\n' "$*" >&2; exit 1; }

envs=$(sh "$(dirname "$0")/detect-envs.sh") || die "could not infer the machine set"
[ -n "$envs" ] || die "the inferred machine set is empty; set DOTFILES_ENVS"

mise=$HOME/.local/bin/mise
# An empty MISE_VERSION makes the official installer resolve the latest stable
# release and verify its checksum; 0s removes its default 24-hour delay. It
# keeps a newer binary that is already installed.
curl -fsSL --proto '=https' --tlsv1.2 https://mise.run \
    | MISE_VERSION='' MISE_MINIMUM_RELEASE_AGE=0s MISE_INSTALL_HELP=0 sh \
    || die "the official mise installer failed"
[ -x "$mise" ] || die "the official installer did not write $mise"
printf 'install-mise: %s for %s\n' "$("$mise" --version)" "$envs"

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
    --from "$REPO_URL" --from-dir "$CHECKOUT" --config-dir global \
    -E "$envs" --prompt-vars --save-env --skip user --update --yes "$@"
