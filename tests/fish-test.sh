#!/usr/bin/env bash
# Behavioral tests for fish: clones the pinned plugins and applies dotfiles
# into a throwaway HOME, then starts fish. Needs mise, fish, git, and network
# for the plugin clones; skips otherwise.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
mise_bin=${MISE_BIN:-$(command -v mise || true)}
fish_bin=${FISH_BIN:-$(command -v fish || true)}
if [ -z "$mise_bin" ] || [ -z "$fish_bin" ]; then
    printf 'skip fish tests (mise or fish not installed)\n'
    exit 0
fi

# Physical, because git reports worktrees by their real path (/private/var on macOS).
tmp=$(cd -P -- "$(mktemp -d)" && pwd) || exit 1
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
base_path=/usr/bin:/bin:/usr/sbin:/sbin
# The fish and zoxide under test are whichever this host has.
ln -s "$fish_bin" "$h/.local/bin/fish"
# The real binary, not a mise shim: a shim would read this checkout's config.
zoxide_bin=$("$mise_bin" which zoxide 2>/dev/null || command -v zoxide || true)
[ -n "$zoxide_bin" ] && ln -s "$zoxide_bin" "$h/.local/bin/zoxide"
for tool in fzf fd rg; do
    bin=$("$mise_bin" which "$tool" 2>/dev/null || command -v "$tool" || true)
    [ -n "$bin" ] && ln -s "$bin" "$h/.local/bin/$tool"
done
# Stand-ins, so the greeting and the desktop guard are observable.
printf '#!/bin/sh\necho PFETCH\n' >"$h/.local/bin/pfetch"
printf '#!/bin/sh\n' >"$h/.local/bin/gtrash"
chmod +x "$h/.local/bin/pfetch" "$h/.local/bin/gtrash"
mkdir -p "$h/.ssh"

# A personal machine: base plus desktop and identity, as on smorespro.
if env -i HOME="$h" PATH="$base_path" TERM=dumb MISE_ENV=desktop,identity \
        MISE_TRUSTED_CONFIG_PATHS="$root" MISE_YES=1 \
        "$mise_bin" -C "$root" bootstrap --only repos,dotfiles --yes >"$tmp/bootstrap.log" 2>&1; then
    ok "repos and dotfiles apply"
else
    no "repos and dotfiles apply"
    sed 's/^/     /' "$tmp/bootstrap.log" >&2
fi

fi_() {  # fi_ <script>: run inside an interactive fish in the test HOME
    (cd "$h" && env -i HOME="$h" PATH="$base_path" TERM=xterm-256color \
        "$h/.local/bin/fish" -i -c "$1" </dev/null) 2>"$tmp/fi.err"
}
fc_() {  # fc_ <script>: run inside a non-interactive fish
    (cd "$h" && env -i HOME="$h" PATH="$base_path" "$h/.local/bin/fish" -c "$1" </dev/null) 2>"$tmp/fc.err"
}

expect "non-interactive fish imports the shared env" "$h/.local/bin bat hx" \
    "$(fc_ 'echo $PATH[1] $PAGER $EDITOR')"
expect "non-interactive fish starts cleanly" "" "$(cat "$tmp/fc.err")"

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
if [ -n "$zoxide_bin" ]; then
    expect "zoxide jumps with c" yes "$(fi_ 'functions -q c; and echo yes')"
fi
expect "interactive startup writes nothing to stderr" "" "$(cat "$tmp/fi.err")"

# --- abbreviations

exp_() {  # exp_ <name> [home]: an abbreviation's expansion, or nothing
    local home=${2:-$h}
    (cd "$home" && env -i HOME="$home" PATH="$base_path" TERM=xterm-256color \
        "$home/.local/bin/fish" -i -c "abbr --show | string match -- 'abbr -a -- $1 *' \
            | string replace -- 'abbr -a -- $1 ' 'printf %s\\n ' | source" </dev/null) 2>/dev/null
}

expect "e opens Helix" hx "$(exp_ e)"
expect "f opens yazi" yazi "$(exp_ f)"
expect "g opens lazygit" lazygit "$(exp_ g)"
expect "l lists long, directories first" 'eza --icons --group-directories-first -lh' "$(exp_ l)"
expect "m makes parents" 'mkdir -p' "$(exp_ m)"
expect "t attaches the main zellij session" 'zellij a -c main' "$(exp_ t)"
expect "a starts maki" maki "$(exp_ a)"
expect "s opens sdlc" sdlc "$(exp_ s)"
expect "d pulls and bootstraps the dotfiles" \
    'git -C ~/.dotfiles pull --ff-only --no-rebase --autostash && mise -C ~/.dotfiles bootstrap' "$(exp_ d)"
expect "gw is git worktree" 'git worktree' "$(exp_ gw)"
expect "copy goes through Clipboard" 'cb copy' "$(exp_ copy)"
expect "paste goes through Clipboard" 'cb paste' "$(exp_ paste)"
expect "gc clones with git get" 'git get' "$(exp_ gc)"
expect "sm opens fish on smortress" 'ssh smortress -t fish' "$(exp_ sm)"
for gone in b la gp gq dv dot boot ms wn cr; do
    expect "the retired abbreviation $gone stays gone" "" "$(exp_ "$gone")"
done
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

expect "r lists every worktree of every repo" "JUMP $repo_root/github.com/o/r/feat" \
    "$(pick_ r feat "$h" /srv/git "$repo_root")"
expect "w jumps to a worktree of this repo" "JUMP $repo_root/github.com/o/r/feat" \
    "$(pick_ w feat "$repo_root/github.com/o/r/main")"
expect "w never offers the bare gitdir" "" \
    "$(pick_ w "'$repo_root/github.com/o/r\$" "$repo_root/github.com/o/r/main")"
expect "ef opens the picked file" "OPEN src/hay.txt" "$(pick_ ef hay "$tmp/proj")"
expect "et opens Helix at the matching line" "OPEN src/hay.txt:2" "$(pick_ et needle "$tmp/proj")"
expect "a cancelled pick runs nothing" "" "$(pick_ ef zzz-no-match "$tmp/proj")"
expect "a cancelled pick prints nothing" "" "$(cat "$tmp/pick.err")"

# --- work machine

hw=$tmp/work
mkdir -p "$hw/.local/bin"
ln -s "$fish_bin" "$hw/.local/bin/fish"
if env -i HOME="$hw" PATH="$base_path" TERM=dumb MISE_ENV=desktop,work \
        MISE_TRUSTED_CONFIG_PATHS="$root" MISE_YES=1 \
        "$mise_bin" -C "$root" dot apply >"$tmp/work.log" 2>&1; then
    ok "work dotfiles apply"
else
    no "work dotfiles apply"
    sed 's/^/     /' "$tmp/work.log" >&2
fi
expect "a starts claude on work" claude "$(exp_ a "$hw")"
expect "r lists the flat work clones" \
    'path dirname ~/Blitzy/*/.git ~/Blitzy/*/.worktrees/*/.git | fzf | read f; and c $f' "$(exp_ r "$hw")"
expect "work has no git get" "" "$(exp_ gc "$hw")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
