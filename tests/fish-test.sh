#!/usr/bin/env bash
# Clones the pinned plugins and applies dotfiles into a throwaway HOME, then
# starts fish. Needs mise, fish, and network for the plugin clones.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

mise_bin=${MISE_BIN:-$(command -v mise || true)}
# The real binary, not a mise shim: a shim would read this checkout's config.
# Debian and Ubuntu ship fd as fdfind.
real_bin() {
    "$mise_bin" which "$1" 2>/dev/null || command -v "$1" || { [ "$1" = fd ] && command -v fdfind; }
}
fish_bin=${FISH_BIN:-$(real_bin fish)}
[ -n "$mise_bin" ] && [ -n "$fish_bin" ] || skip_all "mise or fish not installed"

h=$tmp/home
mkdir -p "$h/.local/bin"
base_path=/usr/bin:/bin:/usr/sbin:/sbin
ln -s "$fish_bin" "$h/.local/bin/fish"
for tool in zoxide fzf fd rg; do
    bin=$(real_bin "$tool") && ln -s "$bin" "$h/.local/bin/$tool"
done
# Stand-ins, so the greeting and the desktop guard are observable.
printf '#!/bin/sh\necho PFETCH\n' >"$h/.local/bin/pfetch"
printf '#!/bin/sh\n' >"$h/.local/bin/gtrash"
chmod +x "$h/.local/bin/pfetch" "$h/.local/bin/gtrash"
mkdir -p "$h/.ssh"

mise_in() {  # mise_in <home> <env set> <args...>
    local home=$1 env=$2
    shift 2
    env -i HOME="$home" PATH="$base_path" TERM=dumb MISE_ENV="$env" \
        MISE_TRUSTED_CONFIG_PATHS="$root" MISE_YES=1 "$mise_bin" -C "$root" "$@"
}
fish_at() {  # fish_at <home> <fish args...>: stderr lands in $tmp/fish.err
    local home=$1
    shift
    (cd "$home" && env -i HOME="$home" PATH="$base_path" TERM=xterm-256color \
        "$home/.local/bin/fish" "$@" </dev/null) 2>"$tmp/fish.err"
}
fi_() { fish_at "$h" -i -c "$1"; }
fc_() { fish_at "$h" -c "$1"; }

# A personal machine: base plus desktop and identity, as on smorespro.
assert "repos and dotfiles apply" mise_in "$h" desktop,identity bootstrap --only repos,dotfiles --yes

expect "non-interactive fish imports the shared env" "$h/.local/bin bat hx" \
    "$(fc_ 'echo $PATH[1] $PAGER $EDITOR')"
expect "non-interactive fish starts cleanly" "" "$(cat "$tmp/fish.err")"
printf 'tok-fish\n' >"$h/.config/gh/token"
expect "fish exports GH_TOKEN for agents it starts" tok-fish "$(fc_ 'echo $GH_TOKEN')"
rm "$h/.config/gh/token"
expect "fish drops a ZDOTDIR inherited from an older session" clear \
    "$( (cd "$h" && env -i HOME="$h" PATH="$base_path" ZDOTDIR=/old "$h/.local/bin/fish" -c \
        'set -q ZDOTDIR; and echo leaked; or echo clear' </dev/null) 2>&1)"
expect "names fish cannot hold are skipped quietly" started \
    "$( (cd "$h" && env -i HOME="$h" PATH="$base_path" 'a.b=1' 'BASH_FUNC_x%%=() { :; }' \
        "$h/.local/bin/fish" -c 'echo started' </dev/null) 2>&1)"

expect "pure is the prompt" yes \
    "$(fi_ 'string match -q "*/fish-plugins/pure/*" (functions --details fish_prompt); and echo yes; or echo no')"
expect "async-prompt renders pure's git segment" "yes _pure_prompt_git" \
    "$(fi_ 'functions -q __async_prompt_fire; and echo yes $async_prompt_functions')"
expect "container detection is off" false "$(fi_ 'echo $pure_enable_container_detection')"
expect "done is loaded" 1.21.1 "$(fi_ 'echo $__done_version')"
expect "done waits 10 seconds" 10000 "$(fi_ 'echo $__done_min_cmd_duration')"
expect "done skips the interactive tools" yes \
    "$(fi_ 'string match -rq -- $__done_exclude[1] "hx foo"; and string match -rq -- $__done_exclude[1] claude; and echo yes')"
expect "the greeting is pfetch" PFETCH "$(fi_ fish_greeting)"
if [ -e "$h/.local/bin/zoxide" ]; then
    expect "zoxide jumps with c" yes "$(fi_ 'functions -q c; and echo yes')"
fi
expect "interactive startup writes nothing to stderr" "" "$(cat "$tmp/fish.err")"

# --- zellij tab naming

# A function shadows any installed helper, and $h/.local/bin is a symlink farm
# into the checkout: writing a stand-in there would edit the repository.
zj_fn="function zellij-tab-name; echo \$argv[1] >>$tmp/tab-name; end"
zj_() {  # zj_ <fish code>: interactive fish in a zellij pane
    (cd "$h" && env -i HOME="$h" PATH="$base_path" TERM=xterm-256color ZELLIJ=0 \
        "$h/.local/bin/fish" -i -c "$zj_fn; $1" </dev/null) 2>"$tmp/zj.err"
}
rm -f "$tmp/tab-name"
zj_ 'emit fish_prompt; emit fish_prompt'
expect "a zellij pane names its tab once, after its folder" "~" \
    "$(cat "$tmp/tab-name" 2>/dev/null)"
expect "naming the tab says nothing" "" "$(cat "$tmp/zj.err")"
rm -f "$tmp/tab-name"
(cd "$h" && env -i HOME="$h" PATH="$base_path" TERM=xterm-256color \
    "$h/.local/bin/fish" -i -c "$zj_fn; emit fish_prompt" </dev/null) 2>/dev/null
expect "no tab is named outside zellij" "" "$(cat "$tmp/tab-name" 2>/dev/null)"

# --- abbreviations

exp_() {  # exp_ <name> [home]: an abbreviation's expansion, or nothing
    fish_at "${2:-$h}" -i -c "abbr --show | string match -- 'abbr -a -- $1 *' \
        | string replace -- 'abbr -a -- $1 ' 'printf %s\\n ' | source"
}

expect "e opens Helix" hx "$(exp_ e)"
expect "f opens yazi" yazi "$(exp_ f)"
expect "g opens lazygit" lazygit "$(exp_ g)"
expect "l lists long, directories first" 'eza --icons --group-directories-first -lh' "$(exp_ l)"
expect "m makes parents" 'mkdir -p' "$(exp_ m)"
expect "t attaches the main zellij session" 'zellij a -c main' "$(exp_ t)"
expect "a starts maki" maki "$(exp_ a)"
expect "s opens the sdlc picker" 'sdlc pick' "$(exp_ s)"
expect "d pulls, bootstraps, and fails when a dotfile ends up unapplied" \
    "git -C ~/.dotfiles pull --ff-only --no-rebase --autostash && mise -C ~/.dotfiles bootstrap --prune-dotfiles && begin; mise -C ~/.dotfiles dot status --missing --json >/dev/null; or mise -C ~/.dotfiles dot status --missing; end" \
    "$(exp_ d)"
expect "gw is git worktree" 'git worktree' "$(exp_ gw)"
expect "copy is fish's clipboard copy, with OSC 52" fish_clipboard_copy "$(exp_ copy)"
expect "paste is fish's clipboard paste" fish_clipboard_paste "$(exp_ paste)"
expect "gc clones with git get" 'git get' "$(exp_ gc)"
expect "sm opens fish on smortress" 'ssh smortress -t fish' "$(exp_ sm)"
expect "sn opens fish on smoresnet" 'ssh -t root@smoresnet bash -lc fish' "$(exp_ sn)"
if [ "$(uname -s)" = Linux ]; then
    expect "ct empties the trash where gtrash exists" 'gtrash find --rm --force' "$(exp_ ct)"
else
    expect "ct is Linux-only" "" "$(exp_ ct)"
fi

# --- pickers: fzf filters instead of prompting, hx and c report the pick

repo_root=$tmp/repos
git init -q -b main "$tmp/up"
git -C "$tmp/up" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git clone -q --bare "$tmp/up" "$repo_root/github.com/o/r/.git"
git -C "$repo_root/github.com/o/r" worktree add -q "$repo_root/github.com/o/r/main" main
git -C "$repo_root/github.com/o/r" worktree add -q -b feat "$repo_root/github.com/o/r/feat" main
mkdir -p "$tmp/proj/src"
printf 'one\nneedle here\n' >"$tmp/proj/src/hay.txt"

# stdin is /dev/null throughout: at a prompt it is the terminal, and rg with no
# path searches a piped stdin instead of the directory.
pick_() {  # pick_ <abbr> <query> <dir> [from] [to]: run the picker non-interactively
    local exp
    exp=$(exp_ "$1")
    [ -n "${4:-}" ] && exp=${exp//"$4"/"$5"}
    (cd "$3" && env -i HOME="$h" PATH="$base_path" TERM=xterm-256color "$h/.local/bin/fish" -i -c "
        function hx; echo OPEN \$argv; end
        function c; echo JUMP \$argv; end
        $(printf '%s' "$exp" | sed "s/fzf/fzf --filter=$2/")" </dev/null) 2>"$tmp/pick.err"
}

if [ -e "$h/.local/bin/fzf" ] && [ -e "$h/.local/bin/fd" ] && [ -e "$h/.local/bin/rg" ]; then
    expect "r lists every worktree of every repo" "JUMP $repo_root/github.com/o/r/feat" \
        "$(pick_ r feat "$h" /srv/git "$repo_root")"
    expect "w jumps to a worktree of this repo" "JUMP $repo_root/github.com/o/r/feat" \
        "$(pick_ w feat "$repo_root/github.com/o/r/main")"
    expect "w never offers the bare gitdir" "" \
        "$(pick_ w "'(bare)" "$repo_root/github.com/o/r/main")"
    expect "ef opens the picked file" "OPEN src/hay.txt" "$(pick_ ef hay "$tmp/proj")"
    expect "et opens Helix at the matching line" "OPEN src/hay.txt:2" "$(pick_ et needle "$tmp/proj")"
    expect "a cancelled pick runs nothing" "" "$(pick_ ef zzz-no-match "$tmp/proj")"
    expect "a cancelled pick prints nothing" "" "$(cat "$tmp/pick.err")"
else
    printf 'skip picker runs (fzf, fd or rg not installed)\n'
fi

# --- work machine

hw=$tmp/work
mkdir -p "$hw/.local/bin" "$hw/.pyenv/shims" "$hw/.nvm/versions/node/v9.0.0/bin" \
    "$hw/.nvm/versions/node/v24.1.0/bin" "$hw/.local/share/mise/shims"
ln -s "$fish_bin" "$hw/.local/bin/fish"
zsh_bin=$(usable_shell zsh || true)
[ -n "$zsh_bin" ] && ln -s "$zsh_bin" "$hw/.local/bin/zsh"
# blitzy-dev's helpers in the real file's shape: top-level resets, a switch
# that unsets the previous env file's variables, hyphenated aliases.
cat >"$hw/blitzy_env_functions.sh" <<'EOF'
_BLITZY_CURRENT_ENV_FILE=""
export BLITZY_ENV=""
set_env() { set -a; . "$1"; set +a; }
blitzy_unload_env() { while IFS= read -r l; do unset "${l%%=*}"; done <"$1"; }
blitzy_switch_env() {
    [ -n "$_BLITZY_CURRENT_ENV_FILE" ] && blitzy_unload_env "$_BLITZY_CURRENT_ENV_FILE"
    _BLITZY_CURRENT_ENV_FILE=$2
    set_env "$2"
    export BLITZY_ENV=$1
}
fails() { return 3; }
alias set-env='set_env'
export PATH="$HOME/.local/bin:$PATH"
EOF
printf 'FOO_A=1\nFOO_B="two words"\n' >"$hw/e1.env"
printf 'FOO_C=3\n' >"$hw/e2.env"
assert "work dotfiles apply" mise_in "$hw" desktop,work dot apply
expect "a starts claude on work" claude "$(exp_ a "$hw")"
expect "r lists the flat work clones" \
    'path dirname ~/Blitzy/*/.git ~/Blitzy/*/.worktrees/*/.git | fzf | read f; and c $f' "$(exp_ r "$hw")"
expect "work has no git get" "" "$(exp_ gc "$hw")"
expect "sm opens fish on smortress from work" 'ssh smortress -t fish' "$(exp_ sm "$hw")"
expect "sn opens fish on smoresnet from work" 'ssh -t root@smoresnet bash -lc fish' "$(exp_ sn "$hw")"

fw_() { fish_at "$hw" -i -c "$1"; }
expect "the employer toolchains follow the mise shims, newest node first" \
    "$hw/.local/share/mise/shims $hw/.pyenv/shims $hw/.nvm/versions/node/v24.1.0/bin" \
    "$(fw_ 'set -l i (contains -i -- ~/.local/share/mise/shims $PATH); echo $PATH[$i..(math $i + 2)]')"
expect "1Password unlocks with biometrics" true "$(fw_ 'echo $OP_BIOMETRIC_UNLOCK_ENABLED')"
expect "a nested work fish adds each toolchain entry once" 1 \
    "$(fw_ 'fish -i -c "count (string match -- ~/.pyenv/shims \$PATH)"')"
expect "pyenv and nvm find their roots" "$hw/.pyenv $hw/.nvm" "$(fw_ 'echo $PYENV_ROOT $NVM_DIR')"
if [ -n "$zsh_bin" ]; then
    expect "every blitzy helper and alias gets a wrapper, private ones excepted" yes \
        "$(fw_ 'functions -q set_env set-env blitzy_switch_env fails; and not functions -q _BLITZY_CURRENT_ENV_FILE; and echo yes')"
    expect "a helper's exports reach fish" "1|two words" \
        "$(fw_ 'set-env ~/e1.env; echo "$FOO_A|$FOO_B"')"
    expect "switching envs unsets the previous env's variables" "unset 3 local" \
        "$(fw_ 'blitzy_switch_env local ~/e1.env; blitzy_switch_env local ~/e2.env
                set -q FOO_A; and echo set; or echo unset; echo $FOO_C $BLITZY_ENV' | tr '\n' ' ' | sed 's/ $//')"
    expect "a helper's exit status comes back" 3 "$(fw_ 'fails; echo $status')"
    expect "running helpers leaves PATH as it was" same \
        "$(fw_ 'set -l p "$PATH"; set-env ~/e1.env; test "$PATH" = "$p"; and echo same')"
expect "the work machine starts cleanly" "" "$(cat "$tmp/fish.err")"
fi

finish
