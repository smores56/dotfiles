#!/usr/bin/env bash
# Behavioral tests for the interactive zsh: clones the pinned zim modules and
# applies dotfiles into a throwaway HOME, builds zim, then starts `zsh -i`.
# Needs mise, zsh, git, and network for the module clones; skips otherwise.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
mise_bin=${MISE_BIN:-$(command -v mise || true)}
zsh_bin=$(command -v zsh || true)
if [ -z "$mise_bin" ] || [ -z "$zsh_bin" ]; then
    printf 'skip shell tests (mise or zsh not installed)\n'
    exit 0
fi

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
expect() {  # expect <desc> <want> <got>
    if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$2', got '$3')"; fi
}

h=$tmp/home
mkdir -p "$h/.local/bin"
# The zsh under test is whichever one this host has; Linux machines get the
# same link from the bootstrap task.
ln -s "$zsh_bin" "$h/.local/bin/zsh"
base_path=$h/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin

run_mise() {
    env -i HOME="$h" PATH="$base_path" TERM=dumb MISE_TRUSTED_CONFIG_PATHS="$root" MISE_YES=1 \
        "$mise_bin" -C "$root" "$@"
}

if run_mise bootstrap --only repos,dotfiles --yes >"$tmp/bootstrap.log" 2>&1; then
    ok "repos and dotfiles apply"
else
    no "repos and dotfiles apply"
    sed 's/^/     /' "$tmp/bootstrap.log" >&2
fi
hz=$tmp/home-no-zsh
mkdir -p "$hz/.config/zsh"
env -i HOME="$hz" PATH="$base_path" sh "$root/scripts/zim-build.sh" >"$tmp/zim-skip.log" 2>&1
expect "zim-build skips while the zsh config is not deployed" "0:no" \
    "$?:$([ -e "$hz/.config/zsh/.zimrc" ] && echo yes || echo no)"
if env -i HOME="$h" PATH="$base_path" sh "$root/scripts/zim-build.sh" >"$tmp/zim.log" 2>&1; then
    ok "zim builds from the cloned modules"
else
    no "zim builds from the cloned modules"
    sed 's/^/     /' "$tmp/zim.log" >&2
fi

dirty=""
for repo in "$h"/.local/share/zsh-plugins/*/; do
    [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ] && dirty="$dirty $(basename "$repo")"
done
expect "zim's compiled files leave the plugin checkouts clean" "" "$dirty"

zi() {  # zi <script>: run inside an interactive zsh in the test HOME
    # The distro zshrc starts compinit before the config; zim completion owns
    # it, and on a runner without a tty the distro call aborts noisily.
    env -i HOME="$h" PATH="$base_path" TERM=xterm-256color skip_global_compinit=1 \
        "$zsh_bin" -i -c "$1" 2>"$tmp/zi.err"
}

for fn in abbr prompt_pure_setup _zsh_autosuggest_start -ftb-complete \
        fast-theme ef et; do
    expect "zsh -i defines $fn" yes "$(zi "(( \$+functions[$fn] )) && print yes || print no")"
done
if [ "$(uname -s)" = Darwin ] || command -v notify-send >/dev/null 2>&1; then
    expect "auto-notify loads when notifications are available" yes \
        "$(zi '(( $+functions[_auto_notify_send] )) && print yes || print no')"
else
    expect "auto-notify stays off without notify-send" no \
        "$(zi '(( $+functions[_auto_notify_send] )) && print yes || print no')"
fi
expect "pure is the prompt" yes "$(zi '(( ${precmd_functions[(Ie)prompt_pure_precmd]} )) && print yes || print no')"
expect "abbreviation e expands to hx" hx "$(zi 'abbr expand e')"
expect "abbreviation g expands to lazygit" lazygit "$(zi 'abbr expand g')"
expect "abbreviation s expands to the sdlc picker" 'sdlc ui' "$(zi 'abbr expand s')"
expect "the shared abbreviations are session abbreviations" yes \
    "$(zi 'abbr list-abbreviations --session | grep -qx "\"e\"" && print yes || print no')"
expect "abbreviations are session-scoped, not written to a file" no \
    "$(zi '[[ -s ${ABBR_USER_ABBREVIATIONS_FILE} ]] && print yes || print no')"
expect "r jumps through the picker function" yes \
    "$(zi '(( $+functions[r] )) && print yes || print no')"
expect "w jumps through the picker function" yes \
    "$(zi '(( $+functions[w] )) && print yes || print no')"
expect "abbreviation gq expands to ghq" ghq "$(zi 'abbr expand gq')"
expect "abbreviation gw expands to git worktree" 'git worktree' "$(zi 'abbr expand gw')"
expect "abbreviation gc expands to git get" 'git get' "$(zi 'abbr expand gc')"
expect "the wrapper abbreviation cr is gone" no \
    "$(zi 'abbr list-abbreviations --session | grep -qx "\"cr\"" && print yes || print no')"
expect "the wrapper abbreviation wn is gone" no \
    "$(zi 'abbr list-abbreviations --session | grep -qx "\"wn\"" && print yes || print no')"
expect "autosuggestions use abbreviations, then history" "abbreviations history" \
    "$(zi 'print -r -- $ZSH_AUTOSUGGEST_STRATEGY')"
expect "history lives in ~/.zsh_history" "$h/.zsh_history" "$(zi 'print -r -- $HISTFILE')"
expect "history keeps 50000 entries" 50000 "$(zi 'print -r -- $SAVEHIST')"
expect "zim state stays out of ZDOTDIR" no \
    "$(zi 'ls -A $ZDOTDIR | grep -qE "zcompdump|^\\.zim$|init\\.zsh|\\.zwc$" && print yes || print no')"
expect "interactive startup writes nothing to stderr" "" "$(cat "$tmp/zi.err")"
expect "abbreviation dot keeps its && and ~ literal" \
    'git -C ~/.dotfiles pull --ff-only --no-rebase --autostash && mise -C ~/.dotfiles dot apply --yes && mise -C ~/.dotfiles dot apply --yes' \
    "$(zi 'abbr expand dot')"
expect "dot applies twice so a moved checkout converges" yes \
    "$(zi 'abbr expand dot | grep -cq "dot apply --yes.*dot apply --yes" && print yes || print no')"
# A renamed conf.d file leaves its old link behind until `mise dot apply --prune`.
ln -s "$tmp/renamed-away.zsh" "$h/.config/zsh/conf.d/50-renamed-away.zsh"
zi : >/dev/null
expect "a dangling conf.d link is skipped silently" "" "$(cat "$tmp/zi.err")"
rm "$h/.config/zsh/conf.d/50-renamed-away.zsh"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
