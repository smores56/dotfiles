#!/usr/bin/env bash
# Behavioral tests for the mise machine definition (mise.toml and its
# environments). Each case applies dotfiles into a throwaway HOME; no real
# $HOME is touched and no network is used. Requires mise on PATH (or MISE_BIN).
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
mise_bin=${MISE_BIN:-$(command -v mise || true)}
if [ -z "$mise_bin" ]; then
    printf 'skip bootstrap tests (mise not installed)\n'
    exit 0
fi

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
assert() {
    local desc=$1
    shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else no "$desc"; fi
}
assert_not() {
    local desc=$1
    shift
    if "$@" >/dev/null 2>&1; then no "$desc"; else ok "$desc"; fi
}
links_into_repo() { [ -L "$1" ] && case $(readlink -- "$1") in "$root"/*) true ;; *) false ;; esac; }

os=$(uname -s)

# run_mise <home> <env> <args...>: mise with a clean environment, trusting only
# this checkout, so no global or user config leaks into the case.
run_mise() {
    local home=$1 env=$2
    shift 2
    env -i HOME="$home" PATH=/usr/bin:/bin:/usr/sbin:/sbin TERM=dumb \
        MISE_ENV="$env" MISE_TRUSTED_CONFIG_PATHS="$root" MISE_YES=1 \
        "$mise_bin" -C "$root" "$@"
}

new_home() {
    local home=$tmp/$1
    mkdir -p "$home"
    printf '%s' "$home"
}

# --- base environment --------------------------------------------------------

h=$(new_home base)
if run_mise "$h" "" dot apply >"$tmp/base.log" 2>&1; then
    ok "base apply exits 0"
else
    no "base apply exits 0"
    sed 's/^/     /' "$tmp/base.log" >&2
fi

for target in \
    .zshenv \
    .config/zsh/.zshenv \
    .config/helix/config.toml \
    .config/helix/languages.toml \
    .config/zellij/config.kdl \
    .config/yazi/yazi.toml \
    .config/lazygit/config.yml \
    .config/television/cable/repos.toml \
    .config/gh/config.yml \
    .config/containers/Containerfile.dev \
    .local/bin/repos \
    .local/bin/worktrees \
    .local/bin/dev \
    .local/bin/sops-age-key \
    .local/bin/maki-session-search \
    .local/bin/maki-session-resume \
    .config/maki/init.lua \
    .agents/skills/sdlc/SKILL.md; do
    assert "base links ~/$target into the checkout" links_into_repo "$h/$target"
done

for target in \
    .gitconfig \
    .ssh/config \
    .aerospace.toml \
    .local/bin/wallpapers \
    .local/bin/tty \
    .config/systemd/user/wallpapers.timer \
    .config/mise; do
    assert_not "base leaves ~/$target alone" test -e "$h/$target"
done

if command -v zsh >/dev/null 2>&1; then
    path_out=$(env -i HOME="$h" PATH=/usr/bin:/bin zsh -c 'print -rl -- $path' 2>/dev/null)
    first=$(printf '%s\n' "$path_out" | sed -n 1p)
    second=$(printf '%s\n' "$path_out" | sed -n 2p)
    assert "non-interactive zsh puts ~/.local/bin first" test "$first" = "$h/.local/bin"
    assert "non-interactive zsh puts mise shims second" \
        test "$second" = "$h/.local/share/mise/shims"
    assert "the system PATH stays after them" grep -qx /usr/bin <<<"$path_out"
    zdot=$(env -i HOME="$h" PATH=/usr/bin:/bin zsh -c 'print -r -- $ZDOTDIR' 2>/dev/null)
    assert "the home zshenv sets ZDOTDIR to the XDG zsh directory" test "$zdot" = "$h/.config/zsh"
else
    printf 'skip zsh PATH checks (zsh not installed)\n'
fi

if run_mise "$h" "" dot unapply >"$tmp/unapply.log" 2>&1; then
    ok "base unapply exits 0"
else
    no "base unapply exits 0"
    sed 's/^/     /' "$tmp/unapply.log" >&2
fi
assert_not "unapply removes the links it created" test -L "$h/.config/helix/config.toml"

# --- conflicts are refused, never overwritten --------------------------------

h=$(new_home conflict)
mkdir -p "$h/.config/helix"
printf 'mine\n' >"$h/.config/helix/config.toml"
run_mise "$h" "" dot apply >"$tmp/conflict.log" 2>&1 </dev/null
assert "a real file in the way is kept" grep -qx mine "$h/.config/helix/config.toml"
assert_not "a real file in the way is not replaced by a link" test -L "$h/.config/helix/config.toml"

# --- identity environment ----------------------------------------------------

h=$(new_home identity)
run_mise "$h" identity dot apply >"$tmp/identity.log" 2>&1 \
    || { no "identity apply exits 0"; sed 's/^/     /' "$tmp/identity.log" >&2; }
assert "identity links ~/.gitconfig" links_into_repo "$h/.gitconfig"
assert "identity links ~/.ssh/config" links_into_repo "$h/.ssh/config"
assert "identity keeps the base links" links_into_repo "$h/.config/helix/config.toml"

# --- desktop environment -----------------------------------------------------

h=$(new_home desktop)
run_mise "$h" desktop dot apply >"$tmp/desktop.log" 2>&1 \
    || { no "desktop apply exits 0"; sed 's/^/     /' "$tmp/desktop.log" >&2; }
assert "desktop keeps the base links" links_into_repo "$h/.local/bin/repos"
assert_not "desktop does not pull in identity" test -e "$h/.gitconfig"
if [ "$os" = Darwin ]; then
    assert "desktop links ~/.aerospace.toml on macOS" links_into_repo "$h/.aerospace.toml"
    assert_not "desktop skips the Linux wallpaper sync on macOS" test -e "$h/.local/bin/wallpapers"
    assert_not "desktop skips the Linux TTY shim on macOS" test -e "$h/.local/bin/tty"
    assert_not "desktop skips systemd units on macOS" test -e "$h/.config/systemd"
else
    assert "desktop links the wallpaper sync on Linux" links_into_repo "$h/.local/bin/wallpapers"
    assert "desktop links the TTY shim on Linux" links_into_repo "$h/.local/bin/tty"
    assert "desktop links the wallpaper timer on Linux" \
        links_into_repo "$h/.config/systemd/user/wallpapers.timer"
    assert_not "desktop skips AeroSpace on Linux" test -e "$h/.aerospace.toml"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
