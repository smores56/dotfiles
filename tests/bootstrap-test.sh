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
    .config/zsh/.zprofile \
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
    login_out=$(env -i HOME="$h" PATH=/usr/bin:/bin zsh -lc 'print -rl -- $path' 2>/dev/null)
    assert "login zsh keeps ~/.local/bin first after the system profile" \
        test "$(printf '%s\n' "$login_out" | sed -n 1p)" = "$h/.local/bin"
    assert "login zsh keeps mise shims second after the system profile" \
        test "$(printf '%s\n' "$login_out" | sed -n 2p)" = "$h/.local/share/mise/shims"
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
mkdir -p "$h/.ssh"
printf 'ssh-ed25519 AAAApersonal me@home\n' >"$h/.ssh/id_ed25519.pub"
printf 'ssh-ed25519 AAAAwork me@work\n' >"$h/.ssh/id_work.pub"
set_var() { run_mise "$h" identity vars "$1" >/dev/null 2>&1 || no "save var ${1%%=*}"; }
set_var "git_name=Test O'Neil User"
set_var git_email=me@example.com
set_var work_email=me@work.example
set_var 'work_signing_key=~/.ssh/id_work.pub'
set_var 'work_owners=blitzy-ai blitzy-platform'
set_var 'work_flat_root=~/Blitzy'
if run_mise "$h" identity dot apply >"$tmp/identity.log" 2>&1; then
    ok "identity apply exits 0"
else
    no "identity apply exits 0"
    sed 's/^/     /' "$tmp/identity.log" >&2
fi
assert "identity links ~/.gitconfig" links_into_repo "$h/.gitconfig"
assert "identity links ~/.ssh/config" links_into_repo "$h/.ssh/config"
assert "identity keeps the base links" links_into_repo "$h/.config/helix/config.toml"
for inc in machine personal work; do
    assert "identity renders ~/.config/git/$inc.inc" test -f "$h/.config/git/$inc.inc"
done

# What git resolves per checkout is the contract, not the file text.
gitcfg() { env -i HOME="$h" PATH=/usr/bin:/bin git -C "$1" config --get "$2"; }
mkrepo() { mkdir -p "$1" && git init -q "$1" && { [ -z "${2:-}" ] || git -C "$1" remote add origin "$2"; }; }
mkrepo "$h/repos/github.com/smores56/proj"
mkrepo "$h/wip/elsewhere" git@github.com:blitzy-ai/service.git
mkrepo "$h/Blitzy/flat"
mkrepo "$h/scratch"
assert "the name survives shell quoting" test "$(gitcfg "$h/scratch" user.name)" = "Test O'Neil User"
assert "a personal checkout signs as the personal identity" \
    test "$(gitcfg "$h/repos/github.com/smores56/proj" user.email)" = me@example.com
assert "a personal checkout uses the local flow" \
    test "$(gitcfg "$h/repos/github.com/smores56/proj" smores.flow)" = local
assert "a work remote anywhere uses the work identity" \
    test "$(gitcfg "$h/wip/elsewhere" user.email)" = me@work.example
# shellcheck disable=SC2088 # git keeps the key path as the literal the var holds
assert "a work remote uses the work signing key" \
    test "$(gitcfg "$h/wip/elsewhere" user.signingkey)" = '~/.ssh/id_work.pub'
assert "a work checkout uses the pr flow" test "$(gitcfg "$h/wip/elsewhere" smores.flow)" = pr
assert "the flat work root is work" test "$(gitcfg "$h/Blitzy/flat" user.email)" = me@work.example
assert "an unmatched checkout falls back to the personal identity" \
    test "$(gitcfg "$h/scratch" user.email)" = me@example.com
assert "allowed_signers lists the personal key" \
    grep -qx 'me@example.com namespaces="git" ssh-ed25519 AAAApersonal me@home' "$h/.config/ssh/allowed_signers"
assert "allowed_signers lists the work key" \
    grep -qx 'me@work.example namespaces="git" ssh-ed25519 AAAAwork me@work' "$h/.config/ssh/allowed_signers"
assert "the XDG ssh directory exists for known_hosts" test -d "$h/.config/ssh"

h2=$(new_home identity-bad)
HBAD=$h2
run_mise "$h2" identity vars git_email=me@example.com >/dev/null 2>&1
run_mise "$h2" identity vars "git_name=bad$(printf '\001')name" >/dev/null 2>&1
run_mise "$h2" identity dot apply >"$tmp/identity-bad.log" 2>&1
assert_not "a control character in a var stops the apply" test -e "$HBAD/.config/git/machine.inc"
assert "the refusal names the var" grep -q git_name "$tmp/identity-bad.log"

h3=$(new_home identity-quote)
run_mise "$h3" identity vars git_email=me@example.com >/dev/null 2>&1
run_mise "$h3" identity vars 'git_name=Bad "Quote"' >/dev/null 2>&1
run_mise "$h3" identity dot apply >"$tmp/identity-quote.log" 2>&1
assert_not "a double quote in a var stops the apply" test -e "$h3/.config/git/machine.inc"

h4=$(new_home identity-work)
run_mise "$h4" identity vars git_name=W >/dev/null 2>&1
run_mise "$h4" identity vars git_email=me@example.com >/dev/null 2>&1
run_mise "$h4" identity vars work_owners=blitzy-ai >/dev/null 2>&1
run_mise "$h4" identity dot apply >"$tmp/identity-work.log" 2>&1
assert_not "work owners without a work email stop the apply" test -e "$h4/.config/git/work.inc"

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
