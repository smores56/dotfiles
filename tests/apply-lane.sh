#!/bin/sh
# Applies one environment set into $HOME the way a machine does, and checks the
# result. Host packages and the login shell are skipped: neither belongs to a
# throwaway HOME.
#
# usage: apply-lane.sh <desktop,identity|desktop,work> [mise binary]
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

fail() { printf 'apply-lane: %s\n' "$*" >&2; exit 1; }

case $env_set in
    *identity*) email=sam@sammohr.dev ;;
    *work*) email=smohr@blitzy.com ;;
    *) fail "unknown environment set $env_set" ;;
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

"$mise" bootstrap --from "file://$source?ref=ci-apply" --from-dir "$from_dir" \
    --config-dir global -E "$env_set" --skip packages,user --yes
"$mise" -C "$from_dir" -E "$env_set" dot status

link() { [ -L "$1" ] || fail "$1 is not a link into the checkout"; }
present() { [ -f "$1" ] || fail "$1 is missing"; }
absent() { [ ! -e "$1" ] || fail "$1 should not exist"; }

link "$HOME/.config/fish/config.fish"
link "$HOME/.config/helix/config.toml"
link "$HOME/.config/kitty/kitty.conf"
present "$HOME/.config/mimeapps.list"
link "$HOME/.claude/CLAUDE.md"
link "$HOME/.local/bin/sdlc"
link "$HOME/.agents/skills/sdlc/SKILL.md"
present "$HOME/.config/git/machine.inc"
[ "$(git config --global --includes --get user.email)" = "$email" ] \
    || fail "the git identity did not render"

case $env_set in
    *identity*) present "$HOME/.config/git/work.inc" ;;
    *work*) present "$HOME/.claude/work.md" ;;
esac

case $(uname -s) in
    Linux)
        link "$HOME/.terminfo/x/xterm-kitty"
        grep -q 'shell/env.sh' "$HOME/.bash_profile" \
            || fail "a bash login does not read the shared env"
        grep -q 'shell/env.sh' "$HOME/.bashrc" \
            || fail "an interactive bash does not read the shared env"
        link "$HOME/.local/share/fonts/GoogleSansCode-MONO-VF.ttf"
        absent "$HOME/Library/Fonts/GoogleSansCode-MONO-VF.ttf"
        ;;
    Darwin)
        present "$HOME/Library/Fonts/GoogleSansCode-MONO-VF.ttf"
        absent "$HOME/.local/share/fonts/GoogleSansCode-MONO-VF.ttf"
        present "$HOME/.config/aerospace/aerospace.toml"
        ;;
esac

# kitty and zellij start fish through its shim, from the lockfile. This lane
# clones the plugins for real, so it is also where the plugins' own behaviour is
# checked: tests/fish.bats runs on staged fixtures and never loads them.
fish=$HOME/.local/share/mise/shims/fish
in_fish() { TERM=xterm-256color "$fish" -i -c "$1" </dev/null; }

in_fish 'string match -q "*/fish-plugins/pure/*" (functions --details fish_prompt)' \
    || fail "pure is not the prompt"
in_fish 'functions -q __async_prompt_fire; and contains -- _pure_prompt_git $async_prompt_functions' \
    || fail "async-prompt does not render pure's git segment"
# The version mise.toml pins.
done_version=$(in_fish 'echo $__done_version' || true)
[ "$done_version" = 1.21.1 ] \
    || fail "done is not 1.21.1 (got ${done_version:-nothing})"
in_fish 'abbr -q e' || fail "the abbreviations do not load"
printf 'apply-lane: %s passed\n' "$env_set"
