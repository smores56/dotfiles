#!/bin/sh
# Install or upgrade mise and bootstrap the ~/.dotfiles checkout at the latest
# main. The login shell is skipped (so extra args cannot use `--only`) because
# chsh prompts; run `mise -C ~/.dotfiles bootstrap --only user` afterwards.
#
# usage: [DOTFILES_ENVS=...] install-mise.sh [extra bootstrap args...]
set -eu

REPO_URL=https://github.com/smores56/dotfiles.git
CHECKOUT=$HOME/.dotfiles

die() { printf 'install-mise: %s\n' "$*" >&2; exit 1; }

envs=$(sh "$(dirname "$0")/detect-envs.sh") || die "could not infer the machine set"
[ -n "$envs" ] || die "the inferred machine set is empty; set DOTFILES_ENVS"

mise=$HOME/.local/bin/mise
# An empty MISE_VERSION resolves the latest stable release with a checksum; 0s
# removes the 24-hour release-age delay.
curl -fsSL --proto '=https' --tlsv1.2 https://mise.run \
    | MISE_VERSION='' MISE_MINIMUM_RELEASE_AGE=0s MISE_INSTALL_HELP=0 sh \
    || die "the official mise installer failed"
[ -x "$mise" ] || die "the official installer did not write $mise"
printf 'install-mise: %s for %s\n' "$("$mise" --version)" "$envs"

"$mise" bootstrap \
    --from "$REPO_URL" --from-dir "$CHECKOUT" --config-dir global \
    -E "$envs" --save-env --skip user --update --yes "$@"
