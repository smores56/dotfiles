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
# The zsh each platform logs in with: macOS's own /bin/zsh reads /etc/zprofile
# (path_helper), which a Nix- or Homebrew-built zsh on PATH does not.
if [ "$os" = Darwin ] && [ -x /bin/zsh ]; then
    zsh_bin=/bin/zsh
else
    zsh_bin=$(command -v zsh || true)
fi

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

# The work environment refuses the generated placeholder key. Exercise that,
# then substitute a test key for the rest of the work cases and restore it.
key_file=$root/work/.config/git/work-signing.pub
if grep -q 'replace-with-work-key' "$key_file" 2>/dev/null; then
    hph=$(new_home work-placeholder)
    run_mise "$hph" desktop,work dot apply >"$tmp/work-placeholder.log" 2>&1
    assert_not "the work apply refuses the placeholder signing key" \
        test -e "$hph/.config/git/work-signing.pub"
    assert "the refusal names the placeholder" \
        grep -q replace-with-work-key "$tmp/work-placeholder.log"
    cp "$key_file" "$tmp/work-signing.pub"
    printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFHdsAxdyKJywPFr5/RzDk1isLdil/G1GG67BWTmol0y test@work\n' \
        >"$key_file"
    trap 'cp "$tmp/work-signing.pub" "$key_file"; rm -rf "$tmp"' EXIT
fi

# --- base environment --------------------------------------------------------

h=$(new_home base)
mkdir -p "$h/.claude"
printf '{\n  "theme": "dark",\n  "autoMemoryEnabled": false\n}\n' >"$h/.claude/settings.json"
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
    .config/zellij/themes/ansi.kdl \
    .config/yazi/yazi.toml \
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
    .agents/skills/sdlc/SKILL.md \
    .claude/CLAUDE.md \
    .claude/agents/Explore.md \
    .claude/skills/sdlc/SKILL.md \
    .claude/skills/resolve-pr/scripts/watch-pr.sh; do
    assert "base links ~/$target into the checkout" links_into_repo "$h/$target"
done

if [ "$os" = Darwin ]; then
    assert "base links lazygit where macOS lazygit reads it" \
        links_into_repo "$h/Library/Application Support/lazygit/config.yml"
else
    assert "base links ~/.config/lazygit/config.yml" links_into_repo "$h/.config/lazygit/config.yml"
fi

assert "Claude's auto-memory is on" \
    test "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["autoMemoryEnabled"])' "$h/.claude/settings.json")" = True
assert "Claude's own settings keys survive the merge" grep -q '"theme": "dark"' "$h/.claude/settings.json"
assert "CLAUDE.md imports the machine's work rules" grep -qx '@~/.claude/work.md' "$h/.claude/CLAUDE.md"
assert_not "CLAUDE.md names no retired memory tool" grep -qE 'memory_(search|write)|memory MCP' "$h/.claude/CLAUDE.md"
assert_not "CLAUDE.md carries no work-only rule" grep -q Blitzy "$h/.claude/CLAUDE.md"
for skill in "$root"/maki/skills/*/; do
    name=$(basename "$skill")
    assert "the $name skill reaches Claude Code" links_into_repo "$h/.claude/skills/$name/SKILL.md"
done

assert "the base work.md is the empty placeholder" grep -q 'No machine-specific rules' "$h/.claude/work.md"

for target in \
    .gitconfig \
    .ssh/config \
    .aerospace.toml \
    .local/bin/wallpapers \
    .config/systemd/user/wallpapers.timer \
    .config/mise; do
    assert_not "base leaves ~/$target alone" test -e "$h/$target"
done

if [ -n "$zsh_bin" ]; then
    path_out=$(env -i HOME="$h" PATH=/usr/bin:/bin "$zsh_bin" -c 'print -rl -- $path' 2>/dev/null)
    first=$(printf '%s\n' "$path_out" | sed -n 1p)
    second=$(printf '%s\n' "$path_out" | sed -n 2p)
    assert "non-interactive zsh puts ~/.local/bin first" test "$first" = "$h/.local/bin"
    assert "non-interactive zsh puts mise shims second" \
        test "$second" = "$h/.local/share/mise/shims"
    assert "the system PATH stays after them" grep -qx /usr/bin <<<"$path_out"
    login_out=$(env -i HOME="$h" PATH=/usr/bin:/bin "$zsh_bin" -lc 'print -rl -- $path' 2>/dev/null)
    assert "login zsh keeps ~/.local/bin first after the system profile" \
        test "$(printf '%s\n' "$login_out" | sed -n 1p)" = "$h/.local/bin"
    assert "login zsh keeps mise shims second after the system profile" \
        test "$(printf '%s\n' "$login_out" | sed -n 2p)" = "$h/.local/share/mise/shims"
    zdot=$(env -i HOME="$h" PATH=/usr/bin:/bin "$zsh_bin" -c 'print -r -- $ZDOTDIR' 2>/dev/null)
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
if run_mise "$h" identity dot apply >"$tmp/identity.log" 2>&1; then
    ok "identity apply exits 0"
else
    no "identity apply exits 0"
    sed 's/^/     /' "$tmp/identity.log" >&2
fi
assert "identity links ~/.gitconfig" links_into_repo "$h/.gitconfig"
assert "identity links ~/.ssh/config" links_into_repo "$h/.ssh/config"
assert "identity keeps the base links" links_into_repo "$h/.config/helix/config.toml"
for inc in machine work; do
    assert "identity renders ~/.config/git/$inc.inc" test -f "$h/.config/git/$inc.inc"
done

# What git resolves per checkout is the contract, not the file text.
gitcfg() { env -i HOME="$h" PATH=/usr/bin:/bin git -C "$1" config --get "$2"; }
mkrepo() { mkdir -p "$1" && git init -q "$1" && { [ -z "${2:-}" ] || git -C "$1" remote add origin "$2"; }; }
mkrepo "$h/scratch"
mkrepo "$h/wip/elsewhere" git@github.com:blitzy-ai/service.git
mkrepo "$h/Blitzy/flat"
assert "the personal name is hardcoded" test "$(gitcfg "$h/scratch" user.name)" = "Sam Mohr"
assert "a personal checkout signs as the personal identity" \
    test "$(gitcfg "$h/scratch" user.email)" = sam@sammohr.dev
assert "a personal checkout uses the local flow" \
    test "$(gitcfg "$h/scratch" smores.flow)" = local
assert "the ghq root is /srv/git" test "$(gitcfg "$h/scratch" ghq.root)" = /srv/git
assert "a work remote anywhere uses the work identity" \
    test "$(gitcfg "$h/wip/elsewhere" user.email)" = smohr@blitzy.com
# shellcheck disable=SC2088 # git keeps the literal path the template holds
assert "a work remote uses the work signing key" \
    test "$(gitcfg "$h/wip/elsewhere" user.signingkey)" = '~/.ssh/id_work.pub'
assert "a work checkout uses the pr flow" test "$(gitcfg "$h/wip/elsewhere" smores.flow)" = pr
assert "the flat work root is work" test "$(gitcfg "$h/Blitzy/flat" user.email)" = smohr@blitzy.com
assert "an unmatched checkout falls back to the personal identity" \
    test "$(gitcfg "$h/scratch" user.email)" = sam@sammohr.dev
assert "allowed_signers lists the personal key" \
    grep -qx 'sam@sammohr.dev namespaces="git" ssh-ed25519 AAAApersonal me@home' "$h/.config/ssh/allowed_signers"
assert "allowed_signers lists the work key" \
    grep -qx 'smohr@blitzy.com namespaces="git" ssh-ed25519 AAAAwork me@work' "$h/.config/ssh/allowed_signers"
assert "the XDG ssh directory exists for known_hosts" test -d "$h/.config/ssh"

h5=$(new_home identity-nokeys)
mkdir -p "$h5/.ssh"
if run_mise "$h5" identity dot apply >"$tmp/identity-nokeys.log" 2>&1; then
    ok "a missing key is skipped, not fatal"
else
    no "a missing key is skipped, not fatal"
    sed 's/^/     /' "$tmp/identity-nokeys.log" >&2
fi
assert "the skipped key is reported" grep -q 'not a readable key file' "$tmp/identity-nokeys.log"
assert "work.inc uses the fixed work email" \
    grep -q 'email = "smohr@blitzy.com"' "$h5/.config/git/work.inc"

# --- desktop environment -----------------------------------------------------

h=$(new_home desktop)
run_mise "$h" desktop dot apply >"$tmp/desktop.log" 2>&1 \
    || { no "desktop apply exits 0"; sed 's/^/     /' "$tmp/desktop.log" >&2; }
assert "desktop keeps the base links" links_into_repo "$h/.local/bin/repos"
assert_not "desktop does not pull in identity" test -e "$h/.gitconfig"
if [ "$os" = Darwin ]; then
    assert "desktop links ~/.aerospace.toml on macOS" links_into_repo "$h/.aerospace.toml"
    assert "desktop installs Google Sans Code on macOS" test -f "$h/Library/Fonts/GoogleSansCode-MONO-VF.ttf"
    assert "desktop installs Google Sans Code Italic on macOS" test -f "$h/Library/Fonts/GoogleSansCode-Italic-MONO-VF.ttf"
    assert "desktop links the WezTerm config" links_into_repo "$h/.config/wezterm/wezterm.lua"
    assert_not "desktop skips the Linux wallpaper sync on macOS" test -e "$h/.local/bin/wallpapers"
    assert_not "desktop skips systemd units on macOS" test -e "$h/.config/systemd"
    assert_not "desktop skips the Linux font links on macOS" \
        test -e "$h/.local/share/fonts/GoogleSansCode-MONO-VF.ttf"
else
    assert "desktop links the wallpaper sync on Linux" links_into_repo "$h/.local/bin/wallpapers"
    assert "desktop links the wallpaper timer on Linux" \
        links_into_repo "$h/.config/systemd/user/wallpapers.timer"
    assert "desktop links Google Sans Code on Linux" \
        links_into_repo "$h/.local/share/fonts/GoogleSansCode-MONO-VF.ttf"
    assert "desktop links Google Sans Code Italic on Linux" \
        links_into_repo "$h/.local/share/fonts/GoogleSansCode-Italic-MONO-VF.ttf"
    assert "desktop appends the zsh hand-off to ~/.bash_profile" \
        grep -q 'exec "$HOME/.local/bin/zsh" -l' "$h/.bash_profile"
    assert "the hand-off leaves bash -ilc alone" \
        grep -q 'BASH_EXECUTION_STRING' "$h/.bash_profile"
    assert_not "desktop skips AeroSpace on Linux" test -e "$h/.aerospace.toml"
    assert_not "desktop skips the macOS font copies on Linux" \
        test -e "$h/Library/Fonts/GoogleSansCode-MONO-VF.ttf"
fi

# --- work environment (smoreswork beside home-manager) -----------------------

h=$(new_home work)
printf 'export EMPLOYER_RC_TEST=1\n' >"$h/.zshrc"
run_mise "$h" desktop,work dot apply >"$tmp/work.log" 2>&1 \
    || { no "work apply exits 0"; sed 's/^/     /' "$tmp/work.log" >&2; }
assert "work links the zsh environment hook" links_into_repo "$h/.config/zsh/env.d/work.zsh"
assert "work links the interactive work hook" links_into_repo "$h/.config/zsh/conf.d/90-work.zsh"
assert "work links the Claude work rules" grep -q 'This is a work host' "$h/.claude/work.md"
assert "work leaves the employer's ~/.zshrc a plain file" test ! -L "$h/.zshrc"
if [ -n "$zsh_bin" ]; then
    assert "non-interactive zsh points SSH at the 1Password agent" \
        bash -c "env -i HOME='$h' PATH=/usr/bin:/bin '$zsh_bin' -c 'print -r -- \$SSH_AUTH_SOCK' | grep -q 2BUA8C4S2C.com.1password"
    assert "non-interactive zsh builds with Apple clang" \
        test "$(env -i HOME="$h" PATH=/usr/bin:/bin "$zsh_bin" -c 'print -r -- $CC')" = /usr/bin/clang
    assert "non-interactive zsh keeps ~/.local/bin first after the hook" \
        test "$(env -i HOME="$h" PATH=/usr/bin:/bin "$zsh_bin" -c 'print -r -- $path[1]')" = "$h/.local/bin"
    login_path=$(env -i HOME="$h" PATH=/usr/bin:/bin "$zsh_bin" -lc 'print -rl -- $path' 2>/dev/null)
    assert "login zsh keeps ~/.local/bin ahead of /usr/bin after path_helper" \
        test "$(printf '%s\n' "$login_path" | sed -n 1p)" = "$h/.local/bin"
    assert_not "the work environment references no Nix path" grep -rqE '/nix/|nix-profile|hm-session' "$root/work"
    assert "interactive zsh sources the employer's ~/.zshrc" \
        test "$(env -i HOME="$h" PATH=/usr/bin:/bin TERM=dumb "$zsh_bin" -ic 'print -r -- ${EMPLOYER_RC_TEST-}' 2>/dev/null)" = 1
fi

# On smoreswork the mise gh is replaced by the 1Password wrapper.
h=$(new_home work-tools)
mkdir -p "$h/.config"
ln -s "$root/global" "$h/.config/mise"
current_tools() {
    (cd / && env -i HOME="$h" PATH=/usr/bin:/bin MISE_ENV="$1" "$mise_bin" ls --current 2>/dev/null | awk '{print $1}')
}
assert "the base tool set includes gh" grep -qx gh <<<"$(current_tools "")"
assert_not "the work environment leaves gh to the 1Password wrapper" grep -qx gh <<<"$(current_tools desktop,work)"
assert_not "the work environment leaves ghq off" grep -qx ghq <<<"$(current_tools desktop,work)"

# --- work identity: work everywhere, signed through 1Password ----------------

h=$(new_home work-identity)
key=$(head -n 1 "$root/work/.config/git/work-signing.pub")
if run_mise "$h" desktop,work dot apply >"$tmp/work-identity.log" 2>&1; then
    ok "work identity apply exits 0"
else
    no "work identity apply exits 0"
    sed 's/^/     /' "$tmp/work-identity.log" >&2
fi
gitcfg() { env -i HOME="$h" PATH=/usr/bin:/bin git -C "$1" config --get "$2"; }
mkdir -p "$h/Blitzy/svc" "$h/scratch"
git init -q "$h/Blitzy/svc"; git -C "$h/Blitzy/svc" remote add origin https://github.com/blitzy-ai/svc.git
git init -q "$h/scratch"
for repo in "$h/Blitzy/svc" "$h/scratch"; do
    assert "$(basename "$repo") commits as the work identity" test "$(gitcfg "$repo" user.email)" = smohr@blitzy.com
done
assert "the work name is hardcoded" test "$(gitcfg "$h/scratch" user.name)" = "Sam Mohr"
assert "commits are signed" test "$(gitcfg "$h/scratch" commit.gpgsign)" = true
assert "signing goes through 1Password" \
    test "$(gitcfg "$h/scratch" gpg.ssh.program)" = /Applications/1Password.app/Contents/MacOS/op-ssh-sign
# shellcheck disable=SC2088 # git keeps the literal path the template holds
assert "the signing key is the checked-in public key" \
    test "$(gitcfg "$h/scratch" user.signingkey)" = '~/.config/git/work-signing.pub'
assert "the work flow is pr" test "$(gitcfg "$h/scratch" smores.flow)" = pr
assert "work branches use the ticket template" test "$(gitcfg "$h/scratch" smores.branchTemplate)" = '{ticket}-{slug}'
assert "https GitHub remotes go over SSH" \
    test "$(env -i HOME="$h" PATH=/usr/bin:/bin git -C "$h/Blitzy/svc" ls-remote --get-url origin)" = git@github.com:blitzy-ai/svc.git
assert "github.com uses the 1Password SSH agent" \
    grep -q 'IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"' "$h/.ssh/config"
assert "the work SSH config offers only the work key" grep -q 'IdentitiesOnly yes' "$h/.ssh/config"
assert "the work public key is deployed" grep -qx "$key" "$h/.config/git/work-signing.pub"
assert "ssh resolves the 1Password agent for github.com" \
    bash -c "env -i HOME='$h' PATH=/usr/bin:/bin ssh -F '$h/.ssh/config' -G github.com | grep -qi 'identityagent .*2BUA8C4S2C.com.1password/t/agent.sock'"
mkdir -p "$h/pub"; git init -q "$h/pub"; git -C "$h/pub" remote add origin https://github.com/someone/public.git
assert "public GitHub remotes stay on https" \
    test "$(env -i HOME="$h" PATH=/usr/bin:/bin git -C "$h/pub" ls-remote --get-url origin)" = https://github.com/someone/public.git
assert "the gh wrapper is first on PATH" links_into_repo "$h/.local/bin/gh"
assert "the gh wrapper knows where the token lives" grep -qx op://Work/GitHub/token "$h/.config/gh-token-ref"

assert "allowed_signers lists the work key" \
    grep -qx "smohr@blitzy.com namespaces=\"git\" $key" "$h/.config/ssh/allowed_signers"

# mise reports an entry whose source is missing as a warning and exits 0.
if grep -h 'matched no files' "$tmp"/*.log >"$tmp/nomatch" 2>/dev/null; then
    no "every dotfile source exists"
    sed 's/^/     /' "$tmp/nomatch" >&2
else
    ok "every dotfile source exists"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
