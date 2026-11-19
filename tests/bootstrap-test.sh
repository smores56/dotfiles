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
    .config/shell/env.sh \
    .config/zsh/.zshenv \
    .config/zsh/.zprofile \
    .config/helix/config.toml \
    .config/helix/languages.toml \
    .config/zellij/config.kdl \
    .config/zellij/themes/ansi.kdl \
    .config/yazi/yazi.toml \
    .config/television/cable/repos.toml \
    .config/gh/config.yml \
    .local/bin/smortress-ssh \
    .local/bin/sops-age-key \
    .local/bin/maki \
    .config/maki/init.lua \
    .config/maki/mcp.toml \
    .config/maki/plugin.toml \
    .config/maki/permissions.toml \
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
for skill in "$root"/sdlc/skills/*/; do
    name=$(basename "$skill")
    assert "the $name skill reaches Claude Code" links_into_repo "$h/.claude/skills/$name/SKILL.md"
done

assert "the base work.md is the empty placeholder" grep -q 'No machine-specific rules' "$h/.claude/work.md"

for target in \
    .gitconfig \
    .ssh/config \
    .ssh/smortress.conf \
    .aerospace.toml \
    .local/bin/wallpapers \
    .config/systemd/user/wallpapers.timer \
    .config/mise; do
    assert_not "base leaves ~/$target alone" test -e "$h/$target"
done

assert "gh clones and checks out over https" grep -qx 'git_protocol: https' "$h/.config/gh/config.yml"

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
    printf 'tok-test\n' >"$h/.config/github-token"
    assert "every zsh exports GH_TOKEN from the token file" \
        test "$(env -i HOME="$h" PATH=/usr/bin:/bin "$zsh_bin" -c 'print -r -- $GH_TOKEN' 2>&1)" = tok-test
    rm "$h/.config/github-token"
    assert "zsh starts cleanly without a token file" \
        test "$(env -i HOME="$h" PATH=/usr/bin:/bin "$zsh_bin" -c 'print -r -- ${GH_TOKEN-unset}' 2>&1)" = unset
    assert "every zsh pages through bat" \
        test "$(env -i HOME="$h" PATH=/usr/bin:/bin "$zsh_bin" -c 'print -r -- $PAGER:$BAT_THEME' 2>&1)" = bat:ansi
    assert "man pages render through bat" \
        test "$(env -i HOME="$h" PATH=/usr/bin:/bin "$zsh_bin" -c 'print -r -- $MANPAGER' 2>&1)" = "sh -c 'col -bx | bat -l man -p'"
else
    printf 'skip zsh PATH checks (zsh not installed)\n'
fi

# Sourcing the shared file again (a login after ~/.zshenv, a nested shell)
# moves its entries to the front instead of adding them twice.
# The middle PATH is what macOS path_helper leaves: system paths moved first.
resourced=$(env -i HOME="$h" PATH=/usr/bin:/bin sh -c \
    '. "$HOME/.config/shell/env.sh"; PATH=/usr/bin:/bin:$HOME/.local/share/mise/shims:$HOME/.local/bin; . "$HOME/.config/shell/env.sh"; printf %s "$PATH"')
assert "re-sourcing the env keeps one copy of each entry, in order" \
    test "$resourced" = "$h/.local/bin:$h/.local/share/mise/shims:/usr/bin:/bin"

for login in -lc -ic; do
    assert "bash $login reads the shared env" \
        test "$(env -i HOME="$h" PATH=/usr/bin:/bin TERM=dumb bash "$login" 'printf %s "${PATH%%:*}:$PAGER"' 2>/dev/null)" = "$h/.local/bin:bat"
done

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
if run_mise "$h" identity dot apply >"$tmp/identity.log" 2>&1; then
    ok "identity apply exits 0"
else
    no "identity apply exits 0"
    sed 's/^/     /' "$tmp/identity.log" >&2
fi
assert "identity links ~/.gitconfig" links_into_repo "$h/.gitconfig"
assert "identity links ~/.ssh/config" links_into_repo "$h/.ssh/config"
assert "identity links the shared smortress route" links_into_repo "$h/.ssh/smortress.conf"
# The route is one file under home/, included by both ssh configs, and the
# wrapper it names is the only place the Access token is read.
assert "the smortress route proxies through the token wrapper" \
    bash -c "env -i HOME='$h' PATH=/usr/bin:/bin ssh -F '$h/.ssh/config' -G smortress 2>/dev/null | grep -qxF 'proxycommand \$HOME/.local/bin/smortress-ssh %h'"
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
assert "git get clones under /srv/git" \
    grep -qF 'd=/srv/git/github.com/' <<<"$(gitcfg "$h/scratch" alias.get)"
assert "the work routing follows the same root" \
    grep -qF 'gitdir:/srv/git/github.com/blitzy-ai/' "$h/.config/git/machine.inc"
assert "a work remote anywhere uses the work identity" \
    test "$(gitcfg "$h/wip/elsewhere" user.email)" = smohr@blitzy.com
assert "a work checkout uses the pr flow" test "$(gitcfg "$h/wip/elsewhere" smores.flow)" = pr
assert "the flat work root is work" test "$(gitcfg "$h/Blitzy/flat" user.email)" = smohr@blitzy.com
assert "an unmatched checkout falls back to the personal identity" \
    test "$(gitcfg "$h/scratch" user.email)" = sam@sammohr.dev
mkrepo "$h/wip/old-personal" ssh://git@github.com/smores56/old.git
mkrepo "$h/wip/https-work" https://github.com/blitzy-ai/other.git
assert "a git@ remote is fetched over https" \
    test "$(env -i HOME="$h" PATH=/usr/bin:/bin git -C "$h/wip/elsewhere" ls-remote --get-url origin)" = https://github.com/blitzy-ai/service.git
assert "an ssh:// remote is fetched over https" \
    test "$(env -i HOME="$h" PATH=/usr/bin:/bin git -C "$h/wip/old-personal" ls-remote --get-url origin)" = https://github.com/smores56/old.git
assert "an https work remote uses the work identity" \
    test "$(gitcfg "$h/wip/https-work" user.email)" = smohr@blitzy.com
for repo in "$h/scratch" "$h/wip/elsewhere"; do
    assert "$(basename "$repo") commits are not signed" test -z "$(gitcfg "$repo" commit.gpgsign)"
done
assert "the XDG ssh directory exists for known_hosts" test -d "$h/.config/ssh"

h5=$(new_home identity-nokeys)
mkdir -p "$h5/.ssh"
if run_mise "$h5" identity dot apply >"$tmp/identity-nokeys.log" 2>&1; then
    ok "identity applies without any SSH keys"
else
    no "identity applies without any SSH keys"
    sed 's/^/     /' "$tmp/identity-nokeys.log" >&2
fi
assert "work.inc uses the fixed work email" \
    grep -q 'email = "smohr@blitzy.com"' "$h5/.config/git/work.inc"

# --- desktop environment -----------------------------------------------------

h=$(new_home desktop)
run_mise "$h" desktop dot apply >"$tmp/desktop.log" 2>&1 \
    || { no "desktop apply exits 0"; sed 's/^/     /' "$tmp/desktop.log" >&2; }
assert "desktop keeps the base links" links_into_repo "$h/.local/bin/smortress-ssh"
assert_not "desktop does not pull in identity" test -e "$h/.gitconfig"
if [ "$os" = Darwin ]; then
    assert "desktop links ~/.aerospace.toml on macOS" links_into_repo "$h/.aerospace.toml"
    assert "desktop installs Google Sans Code on macOS" test -f "$h/Library/Fonts/GoogleSansCode-MONO-VF.ttf"
    assert "desktop installs Google Sans Code Italic on macOS" test -f "$h/Library/Fonts/GoogleSansCode-Italic-MONO-VF.ttf"
    assert "desktop links the kitty config on macOS" links_into_repo "$h/.config/kitty/macos.conf"
    assert_not "desktop skips the Linux wallpaper sync on macOS" test -e "$h/.local/bin/wallpapers"
    assert_not "desktop skips systemd units on macOS" test -e "$h/.config/systemd"
    assert_not "desktop skips the Linux font links on macOS" \
        test -e "$h/.local/share/fonts/GoogleSansCode-MONO-VF.ttf"
else
    assert "desktop links the wallpaper sync on Linux" links_into_repo "$h/.local/bin/wallpapers"
    assert "desktop links the kitty config on Linux" links_into_repo "$h/.config/kitty/kitty.conf"
    assert "desktop copies the mimeapps list on Linux" test -f "$h/.config/mimeapps.list"
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

# --- work environment --------------------------------------------------------

h=$(new_home work)
printf 'export EMPLOYER_RC_TEST=1\n' >"$h/.zshrc"
run_mise "$h" desktop,work dot apply >"$tmp/work.log" 2>&1 \
    || { no "work apply exits 0"; sed 's/^/     /' "$tmp/work.log" >&2; }
assert "work links the shared smortress route" links_into_repo "$h/.ssh/smortress.conf"
assert "the work smortress route is the same wrapper" \
    bash -c "env -i HOME='$h' PATH=/usr/bin:/bin ssh -F '$h/.ssh/config' -G smortress 2>/dev/null | grep -qxF 'proxycommand \$HOME/.local/bin/smortress-ssh %h'"
assert "work links the shared environment additions" links_into_repo "$h/.config/shell/env.d/work.sh"
assert "work links the interactive work hook" links_into_repo "$h/.config/zsh/conf.d/90-work.zsh"
assert "work links the Claude work rules" grep -q 'This is a work host' "$h/.claude/work.md"
assert "work leaves the employer's ~/.zshrc a plain file" test ! -L "$h/.zshrc"
if [ -n "$zsh_bin" ]; then
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

# Every environment, smoreswork included, takes gh from mise.
h=$(new_home work-tools)
mkdir -p "$h/.config"
ln -s "$root/global" "$h/.config/mise"
current_tools() {
    (cd / && env -i HOME="$h" PATH=/usr/bin:/bin MISE_ENV="$1" "$mise_bin" ls --current 2>/dev/null | awk '{print $1}')
}
assert "the base tool set includes gh" grep -qx gh <<<"$(current_tools "")"
assert "the work environment takes gh from mise" grep -qx gh <<<"$(current_tools desktop,work)"

# --- work identity: work everywhere ------------------------------------------

h=$(new_home work-identity)
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
mkdir -p "$h/Blitzy/old"; git init -q "$h/Blitzy/old"; git -C "$h/Blitzy/old" remote add origin git@github.com:blitzy-platform/old.git
assert "an old work ssh remote is fetched over https" \
    test "$(env -i HOME="$h" PATH=/usr/bin:/bin git -C "$h/Blitzy/old" ls-remote --get-url origin)" = https://github.com/blitzy-platform/old.git
for repo in "$h/Blitzy/svc" "$h/scratch"; do
    assert "$(basename "$repo") commits as the work identity" test "$(gitcfg "$repo" user.email)" = smohr@blitzy.com
done
assert "the work name is hardcoded" test "$(gitcfg "$h/scratch" user.name)" = "Sam Mohr"
assert "work commits are not signed" test -z "$(gitcfg "$h/scratch" commit.gpgsign)"
assert "the work flow is pr" test "$(gitcfg "$h/scratch" smores.flow)" = pr
assert "the work machine has no git get" test -z "$(gitcfg "$h/scratch" alias.get)"
assert "work GitHub remotes stay on https" \
    test "$(env -i HOME="$h" PATH=/usr/bin:/bin git -C "$h/Blitzy/svc" ls-remote --get-url origin)" = https://github.com/blitzy-ai/svc.git
assert "the work SSH config has no github.com entry" \
    bash -c "! env -i HOME='$h' PATH=/usr/bin:/bin ssh -F '$h/.ssh/config' -G github.com | grep -qi '^identityagent '"
assert "the work XDG ssh directory exists for known_hosts" test -d "$h/.config/ssh"

# mise reports an entry whose source is missing, or one it cannot apply, as a
# warning and exits 0.
if grep -hE 'matched no files|ignoring entry' "$tmp"/*.log >"$tmp/nomatch" 2>/dev/null; then
    no "every dotfile source exists"
    sed 's/^/     /' "$tmp/nomatch" >&2
else
    ok "every dotfile source exists"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
