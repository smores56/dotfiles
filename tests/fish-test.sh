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
base_path=/usr/bin:/bin:/usr/sbin:/sbin
# The fish and zoxide under test are whichever this host has.
ln -s "$fish_bin" "$h/.local/bin/fish"
# The real binary, not a mise shim: a shim would read this checkout's config.
zoxide_bin=$("$mise_bin" which zoxide 2>/dev/null || command -v zoxide || true)
[ -n "$zoxide_bin" ] && ln -s "$zoxide_bin" "$h/.local/bin/zoxide"
# A stand-in pfetch, so the greeting is observable.
printf '#!/bin/sh\necho PFETCH\n' >"$h/.local/bin/pfetch"
chmod +x "$h/.local/bin/pfetch"

if env -i HOME="$h" PATH="$base_path" TERM=dumb MISE_TRUSTED_CONFIG_PATHS="$root" MISE_YES=1 \
        "$mise_bin" -C "$root" bootstrap --only repos,dotfiles --yes >"$tmp/bootstrap.log" 2>&1; then
    ok "repos and dotfiles apply"
else
    no "repos and dotfiles apply"
    sed 's/^/     /' "$tmp/bootstrap.log" >&2
fi

fi_() {  # fi_ <script>: run inside an interactive fish in the test HOME
    (cd "$h" && env -i HOME="$h" PATH="$base_path" TERM=xterm-256color \
        "$h/.local/bin/fish" -i -c "$1") 2>"$tmp/fi.err"
}
fc_() {  # fc_ <script>: run inside a non-interactive fish
    (cd "$h" && env -i HOME="$h" PATH="$base_path" "$h/.local/bin/fish" -c "$1") 2>"$tmp/fc.err"
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
