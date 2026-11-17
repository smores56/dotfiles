#!/bin/sh
# Apply one environment set into $HOME, the way a machine does, and check the
# result. CI runs this in a Fedora container and on macOS; host packages and the
# login shell are skipped because neither belongs to a throwaway HOME.
#
# usage: apply-lane.sh <env set> [mise binary]
#   env sets: desktop,identity (Linux) and desktop,work (macOS)
#   mise binary defaults to `mise` on PATH
set -eu

env_set=${1:?usage: apply-lane.sh <env set> [mise]}
mise=${2:-mise}
case $mise in
    */*) ;;
    *) mise=$(command -v "$mise") ;;
esac
root=$(cd -- "$(dirname -- "$0")/.." && pwd)

# A machine keeps mise in ~/.local/bin, which the bootstrap task puts on PATH;
# mirror that here so the task can find it.
mkdir -p "$HOME/.local/bin"
[ "$mise" = "$HOME/.local/bin/mise" ] || cp "$mise" "$HOME/.local/bin/mise"
mise=$HOME/.local/bin/mise
PATH=$HOME/.local/bin:$PATH
export PATH

MISE_YES=1
MISE_TRUSTED_CONFIG_PATHS=$root
export MISE_YES MISE_TRUSTED_CONFIG_PATHS

run_mise() {
    "$mise" -C "$root" -E "$env_set" "$@"
}

case $env_set in
    *identity*)
        email=sam@sammohr.dev
        ;;
    *work*)
        email=smohr@blitzy.com
        ;;
    *)
        printf 'apply-lane: unknown environment set %s\n' "$env_set" >&2
        exit 1
        ;;
esac

# Clone the checkout the way a machine bootstraps, so `--config-dir` links the
# global config from a checkout mise owns. The CI checkout can be a PR merge
# commit, which is not advertised as a ref, so name it on a local branch first.
source=$HOME/ci-source
from_dir=$HOME/dotfiles
MISE_TRUSTED_CONFIG_PATHS=$root:$from_dir
export MISE_TRUSTED_CONFIG_PATHS
rm -rf "$source"
cp -a "$root" "$source"
git -C "$source" checkout -q -B ci-apply

# The real run: tools from the lockfiles, the pinned repositories, the
# dotfiles, and the bootstrap task.
"$mise" bootstrap --from "file://$source?ref=ci-apply" --from-dir "$from_dir" \
    --config-dir global -E "$env_set" --skip packages,user --yes
"$mise" -C "$from_dir" -E "$env_set" dot status

fail() { printf 'apply-lane: %s\n' "$*" >&2; exit 1; }

link() { [ -L "$1" ] || fail "$1 is not a link into the checkout"; }
present() { [ -f "$1" ] || fail "$1 is missing"; }
absent() { [ ! -e "$1" ] || fail "$1 should not exist"; }

link "$HOME/.config/zsh/.zshrc"
link "$HOME/.config/helix/config.toml"
link "$HOME/.config/wezterm/wezterm.lua"
link "$HOME/.claude/CLAUDE.md"
link "$HOME/.local/bin/sdlc"
link "$HOME/.agents/skills/sdlc/SKILL.md"
present "$HOME/.config/git/machine.inc"
[ "$(git config --global --includes --get user.email)" = "$email" ] \
    || fail "the git identity did not render"

case $env_set in
    *identity*)
        present "$HOME/.config/git/work.inc"
        [ "$(git config --global --includes --get ghq.root)" = /srv/git ] \
            || fail "ghq.root is not /srv/git"
        ;;
    *work*)
        grep -q 'IdentityAgent' "$HOME/.ssh/config" \
            || fail "the github.com host entry does not use the 1Password agent"
        present "$HOME/.claude/work.md"
        ;;
esac

case $(uname -s) in
    Linux)
        [ -x "$HOME/.local/bin/zsh" ] || fail "the Linux zsh link is missing"
        grep -q 'mise:zsh' "$HOME/.bash_profile" \
            || fail "the bash_profile hand-off block is missing"
        link "$HOME/.local/share/fonts/GoogleSansCode-MONO-VF.ttf"
        absent "$HOME/Library/Fonts/GoogleSansCode-MONO-VF.ttf"
        ;;
    Darwin)
        present "$HOME/Library/Fonts/GoogleSansCode-MONO-VF.ttf"
        absent "$HOME/.local/share/fonts/GoogleSansCode-MONO-VF.ttf"
        present "$HOME/.aerospace.toml"
        ;;
esac

zsh_bin=$HOME/.local/bin/zsh
[ -x "$zsh_bin" ] || zsh_bin=/bin/zsh
TERM=xterm-256color "$zsh_bin" -i -c \
    '(( $+functions[prompt_pure_setup] )) && (( $+functions[abbr] )) && (( $+functions[maki] ))' \
    || fail "the interactive zsh does not load zimfw and the plugin set"

# The conda zsh launcher would export CONDA_* into every child; the link must
# point at the real binary, and no CONDA_* may reach an interactive shell.
if env | grep -q '^CONDA_'; then
    fail "CONDA_* leaked into the environment"
fi
printf 'apply-lane: %s passed\n' "$env_set"
