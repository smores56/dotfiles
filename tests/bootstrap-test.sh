#!/usr/bin/env bash
# Applies each environment into a throwaway HOME; no real $HOME is touched and
# no network is used.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

mise_bin=${MISE_BIN:-$(command -v mise || true)}
[ -n "$mise_bin" ] || skip_all "mise not installed"

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
        "$mise_bin" -C "$root" "$@" 2>&1 | tee -a "$tmp/mise.log"
}

new_home() {
    local home=$tmp/$1
    mkdir -p "$home"
    printf '%s' "$home"
}
in_h() { env -i HOME="$h" PATH=/usr/bin:/bin "$@"; }
# What git resolves per checkout is the contract, not the file text.
gitcfg() { in_h git -C "$1" config --get "$2"; }
url_of() { in_h git -C "$1" ls-remote --get-url origin; }
mkrepo() { mkdir -p "$1" && git init -q "$1" && { [ -z "${2:-}" ] || git -C "$1" remote add origin "$2"; }; }
proxy_of() { in_h ssh -F "$h/.ssh/config" -G "$1" 2>/dev/null | sed -n 's/^proxycommand //p'; }
hostname_of() { in_h ssh -F "$h/.ssh/config" -G "$1" 2>/dev/null | sed -n 's/^hostname //p'; }

# --- base environment --------------------------------------------------------

h=$(new_home base)
mkdir -p "$h/.claude"
printf '{\n  "theme": "dark",\n  "autoMemoryEnabled": false\n}\n' >"$h/.claude/settings.json"
assert "base apply exits 0" run_mise "$h" "" dot apply

for target in \
    .zshenv \
    .config/shell/env.sh \
    .config/fish/config.fish \
    .config/fish/conf.d/20-abbreviations.fish \
    .config/helix/config.toml \
    .config/helix/languages.toml \
    .config/zellij/config.kdl \
    .config/zellij/themes/ansi.kdl \
    .config/yazi/yazi.toml \
    .config/gh/config.yml \
    .local/bin/sops-age-key \
    .local/bin/maki \
    .config/maki/init.lua \
    .config/maki/mcp.toml \
    .config/maki/plugin.toml \
    .config/maki/permissions.toml \
    .agents/skills/sdlc/SKILL.md \
    .claude/CLAUDE.md \
    .claude/agents/Explore.md \
    .claude/skills/sdlc/SKILL.md; do
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
assert_not "CLAUDE.md carries no work-only rule" grep -q Blitzy "$h/.claude/CLAUDE.md"
for skill in "$root"/sdlc/skills/*/; do
    name=$(basename "$skill")
    assert "the $name skill reaches Claude Code" links_into_repo "$h/.claude/skills/$name/SKILL.md"
done

assert "the base work.md is the empty placeholder" grep -q 'No machine-specific rules' "$h/.claude/work.md"

for target in \
    .config/git/config \
    .ssh/config \
    .ssh/smortress.conf \
    .config/aerospace/aerospace.toml \
    .local/bin/wallpapers \
    .config/systemd/user/wallpapers.timer \
    .config/mise; do
    assert_not "base leaves ~/$target alone" test -e "$h/$target"
done

assert "gh clones and checks out over https" grep -qx 'git_protocol: https' "$h/.config/gh/config.yml"

if [ -n "$zsh_bin" ]; then
    path_out=$(in_h "$zsh_bin" -c 'print -rl -- $path' 2>/dev/null)
    first=$(printf '%s\n' "$path_out" | sed -n 1p)
    second=$(printf '%s\n' "$path_out" | sed -n 2p)
    assert "non-interactive zsh puts ~/.local/bin first" test "$first" = "$h/.local/bin"
    assert "non-interactive zsh puts mise shims second" \
        test "$second" = "$h/.local/share/mise/shims"
    assert "the system PATH stays after them" grep -qx /usr/bin <<<"$path_out"
    login_out=$(in_h "$zsh_bin" -lc 'print -rl -- $path' 2>/dev/null)
    assert "login zsh keeps ~/.local/bin first after the system profile" \
        test "$(printf '%s\n' "$login_out" | sed -n 1p)" = "$h/.local/bin"
    assert "login zsh keeps mise shims second after the system profile" \
        test "$(printf '%s\n' "$login_out" | sed -n 2p)" = "$h/.local/share/mise/shims"
    zdot=$(in_h "$zsh_bin" -c 'print -r -- ${ZDOTDIR-unset}' 2>/dev/null)
    assert "zsh keeps its default ZDOTDIR" test "$zdot" = unset
    printf 'tok-test\n' >"$h/.config/gh/token"
    assert "every zsh exports GH_TOKEN from the token file" \
        test "$(in_h "$zsh_bin" -c 'print -r -- $GH_TOKEN' 2>&1)" = tok-test
    rm "$h/.config/gh/token"
    assert "zsh starts cleanly without a token file" \
        test "$(in_h "$zsh_bin" -c 'print -r -- ${GH_TOKEN-unset}' 2>&1)" = unset
    assert "every zsh pages through bat" \
        test "$(in_h "$zsh_bin" -c 'print -r -- $PAGER:$BAT_THEME' 2>&1)" = bat:ansi
    assert "man pages render through bat" \
        test "$(in_h "$zsh_bin" -c 'print -r -- $MANPAGER' 2>&1)" = "sh -c 'col -bx | bat -l man -p'"
else
    printf 'skip zsh PATH checks (zsh not installed)\n'
fi

# Sourcing the shared file again (a login after ~/.zshenv, a nested shell)
# moves its entries to the front instead of adding them twice.
# The middle PATH is what macOS path_helper leaves: system paths moved first.
resourced=$(in_h sh -c \
    '. "$HOME/.config/shell/env.sh"; PATH=/usr/bin:/bin:$HOME/.local/share/mise/shims:$HOME/.local/bin; . "$HOME/.config/shell/env.sh"; printf %s "$PATH"')
assert "re-sourcing the env keeps one copy of each entry, in order" \
    test "$resourced" = "$h/.local/bin:$h/.local/share/mise/shims:/usr/bin:/bin"

if [ -n "$zsh_bin" ]; then
    assert "login zsh gets the env from the ~/.zprofile block" grep -q 'shell/env.sh' "$h/.zprofile"
    printf 'tok-nonl' >"$h/.config/gh/token"
    assert "a token file without a final newline still exports GH_TOKEN" \
        test "$(in_h "$zsh_bin" -c 'print -r -- ${GH_TOKEN-unset}')" = tok-nonl
    rm "$h/.config/gh/token"
    assert "the env drops a ZDOTDIR inherited from an older session" \
        test "$(in_h ZDOTDIR=/old sh -c '. "$HOME/.config/shell/env.sh"; printf %s "${ZDOTDIR-unset}"')" = unset
    mv "$h/.config/shell/env.sh" "$h/env.sh.away"
    assert "zsh -c still runs while env.sh is not linked yet" \
        test "$(in_h "$zsh_bin" -c 'print ok' 2>/dev/null)" = ok
    assert "a login zsh still runs while env.sh is not linked yet" \
        test "$(in_h "$zsh_bin" -lc 'print ok' 2>/dev/null)" = ok
    assert "bash still runs while env.sh is not linked yet" \
        test "$(in_h bash -lc 'echo ok' 2>/dev/null)" = ok
    mv "$h/env.sh.away" "$h/.config/shell/env.sh"
fi

for login in -lc -ic; do
    assert "bash $login reads the shared env" \
        test "$(in_h TERM=dumb bash "$login" 'printf %s "${PATH%%:*}:$PAGER"' 2>/dev/null)" = "$h/.local/bin:bat"
done

assert "base unapply exits 0" run_mise "$h" "" dot unapply
assert_not "unapply removes the links it created" test -L "$h/.config/helix/config.toml"

# --- files other installers own stay theirs ---------------------------------

h=$(new_home installer-owned)
printf 'export PATH="$PATH:$HOME/.docker/bin"\n' >"$h/.zprofile"
assert "an existing ~/.zprofile does not block the apply" run_mise "$h" "" dot apply
assert "the installer's ~/.zprofile line survives" grep -qF '.docker/bin' "$h/.zprofile"
assert "the env block joins it" grep -q 'shell/env.sh' "$h/.zprofile"

# --- conflicts are refused, never overwritten --------------------------------

h=$(new_home conflict)
mkdir -p "$h/.config/helix"
printf 'mine\n' >"$h/.config/helix/config.toml"
run_mise "$h" "" dot apply >/dev/null </dev/null
assert "a real file in the way is kept" grep -qx mine "$h/.config/helix/config.toml"
assert_not "a real file in the way is not replaced by a link" test -L "$h/.config/helix/config.toml"

# --- identity environment ----------------------------------------------------

h=$(new_home identity)
mkdir -p "$h/.ssh"
assert "identity apply exits 0" run_mise "$h" identity dot apply
assert "identity links ~/.config/git/config" links_into_repo "$h/.config/git/config"
assert "identity links ~/.ssh/config" links_into_repo "$h/.ssh/config"
assert "identity links the shared smortress route" links_into_repo "$h/.ssh/smortress.conf"
# The route is one file under home/, included by both ssh configs: the tailnet is
# the only route, so ssh's own transport carries it and nothing proxies.
expect "the smortress route needs no proxy" '' "$(proxy_of smortress)"
expect "the smortress route resolves through MagicDNS" smortress "$(hostname_of smortress)"
expect "the retired tunnel host has no proxy" '' "$(proxy_of ssh.sammohr.dev)"
assert "identity keeps the base links" links_into_repo "$h/.config/helix/config.toml"
for inc in machine work; do
    assert "identity renders ~/.config/git/$inc.inc" test -f "$h/.config/git/$inc.inc"
done

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
mkrepo "$h/wip/old-personal" ssh://git@github.com/smores56/old.git
mkrepo "$h/wip/https-work" https://github.com/blitzy-ai/other.git
assert "a git@ remote is fetched over https" \
    test "$(url_of "$h/wip/elsewhere")" = https://github.com/blitzy-ai/service.git
assert "an ssh:// remote is fetched over https" \
    test "$(url_of "$h/wip/old-personal")" = https://github.com/smores56/old.git
assert "an https work remote uses the work identity" \
    test "$(gitcfg "$h/wip/https-work" user.email)" = smohr@blitzy.com
for repo in "$h/scratch" "$h/wip/elsewhere"; do
    assert "$(basename "$repo") commits are not signed" test -z "$(gitcfg "$repo" commit.gpgsign)"
done

h5=$(new_home identity-nokeys)
mkdir -p "$h5/.ssh"
assert "identity applies without any SSH keys" run_mise "$h5" identity dot apply
assert "work.inc uses the fixed work email" \
    grep -q 'email = "smohr@blitzy.com"' "$h5/.config/git/work.inc"

# --- desktop environment -----------------------------------------------------

h=$(new_home desktop)
assert "desktop apply exits 0" run_mise "$h" desktop dot apply
assert "desktop keeps the base links" links_into_repo "$h/.local/bin/maki"
assert_not "desktop does not pull in identity" test -e "$h/.config/git/config"
if [ "$os" = Darwin ]; then
    assert "desktop links ~/.config/aerospace/aerospace.toml on macOS" links_into_repo "$h/.config/aerospace/aerospace.toml"
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
    # The sudo tap on smortress signs through this agent: without the unit the
    # user has no SSH_AUTH_SOCK to forward.
    assert "desktop links the ssh-agent unit on Linux" \
        links_into_repo "$h/.config/systemd/user/ssh-agent.service"
    assert "the ssh-agent unit binds the shared socket" \
        grep -qF -- '-a %h/.local/state/ssh/agent.sock' "$h/.config/systemd/user/ssh-agent.service"
    assert "the base env exports the agent socket" \
        grep -q 'SSH_AUTH_SOCK' "$h/.config/shell/env.d/10-ssh-agent.sh"
    assert "the bootstrap starts the Linux agent" \
        grep -q 'load_ssh_agent_linux' "$root/scripts/bootstrap-task.sh"
    assert "desktop links Google Sans Code on Linux" \
        links_into_repo "$h/.local/share/fonts/GoogleSansCode-MONO-VF.ttf"
    assert "desktop links Google Sans Code Italic on Linux" \
        links_into_repo "$h/.local/share/fonts/GoogleSansCode-Italic-MONO-VF.ttf"
    assert "desktop links the Linux-only fish abbreviations" \
        links_into_repo "$h/.config/fish/conf.d/80-desktop.fish"
    assert_not "desktop skips AeroSpace on Linux" test -e "$h/.config/aerospace/aerospace.toml"
    assert_not "desktop skips the macOS font copies on Linux" \
        test -e "$h/Library/Fonts/GoogleSansCode-MONO-VF.ttf"
fi

# --- work environment --------------------------------------------------------

h=$(new_home work)
printf 'export EMPLOYER_RC_TEST=1\n' >"$h/.zshrc"
assert "work apply exits 0" run_mise "$h" desktop,work dot apply
assert "work links the shared smortress route" links_into_repo "$h/.ssh/smortress.conf"
# launchd starts at `/` and ssh starts the ProxyCommand outside any checkout, so
# neither can run a mise shim: the bootstrap writes wrappers next to them.
plist=$h/Library/LaunchAgents/dev.sammohr.tailscaled.plist
assert "the tailscaled agent launches the bootstrap's wrapper" \
    grep -qF 'exec "$HOME/.local/bin/tailscaled"' "$plist"
assert "the tailscaled agent creates its state unreadable" \
    grep -qF 'umask 077 &amp;&amp; mkdir -p "$HOME/.local/state/tailscale"' "$plist"
# The sudo tap on smortress asks the client's agent for a signature, so the Mac
# needs an agent that outlives one terminal: a LaunchAgent on a fixed socket.
agent=$h/Library/LaunchAgents/dev.sammohr.ssh-agent.plist
# -D keeps it in the foreground: a forking agent exits 0, so KeepAlive respawns
# it every throttle interval and each respawn deletes the live socket.
assert "the ssh-agent is a foreground LaunchAgent on a fixed socket" \
    grep -qF 'exec /usr/bin/ssh-agent -D -a "$HOME/.local/state/ssh/agent.sock"' "$agent"
assert "the ssh-agent clears a stale socket and creates its directory unreadable" \
    grep -qF 'umask 077 &amp;&amp; mkdir -p "$HOME/.local/state/ssh" &amp;&amp; rm -f' "$agent"
assert "the work shell env exports the agent socket" \
    grep -q 'SSH_AUTH_SOCK=\$HOME/.local/state/ssh/agent.sock' "$h/.config/shell/env.d/work.sh"
assert "the fish work hook exports the agent socket" \
    grep -q 'SSH_AUTH_SOCK' "$h/.config/fish/conf.d/90-work.fish"
# Apple's OpenSSH has no built-in FIDO middleware: without a provider, ssh-add
# refuses the sk handle with "Cannot load FIDO key ... without provider".
assert "the work shell env names Apple's security-key provider" \
    grep -qF 'SSH_SK_PROVIDER=/usr/lib/ssh-keychain.dylib' "$h/.config/shell/env.d/work.sh"
assert "the fish work hook names Apple's security-key provider" \
    grep -qF 'SSH_SK_PROVIDER /usr/lib/ssh-keychain.dylib' "$h/.config/fish/conf.d/90-work.fish"
assert "the bootstrap adds the sudo credentials through the provider" \
    grep -qF 'SSH_SK_PROVIDER=/usr/lib/ssh-keychain.dylib' "$root/scripts/add-sudo-credential.sh"
assert "the bootstrap loads the agent and adds the sudo credentials" \
    grep -qF 'add-sudo-credential.sh' "$root/scripts/bootstrap-task.sh"
expect "the work smortress route goes through the userspace tailscaled" \
    '$HOME/.local/bin/tailscale --socket=$HOME/.local/state/tailscale/tailscaled.sock nc %h %p' \
    "$(proxy_of smortress)"
expect "the work smortress route still resolves through MagicDNS" smortress "$(hostname_of smortress)"
# `accept-new` pins whatever the corporate resolver answered, so the alias keeps
# one known-hosts identity instead of one per answer.
expect "the work smortress route pins one known-hosts identity" smortress \
    "$(in_h ssh -F "$h/.ssh/config" -G smortress 2>/dev/null | sed -n 's/^hostkeyalias //p')"
expect "the work tunnel host has no proxy" '' "$(proxy_of ssh.sammohr.dev)"
assert "work links the shared environment additions" links_into_repo "$h/.config/shell/env.d/work.sh"
assert "work links the fish work hook" links_into_repo "$h/.config/fish/conf.d/90-work.fish"
assert "work links the Claude work rules" grep -q 'This is a work host' "$h/.claude/work.md"
assert "work leaves the employer's ~/.zshrc a plain file" test ! -L "$h/.zshrc"
if [ -n "$zsh_bin" ]; then
    assert "non-interactive zsh builds with Apple clang" \
        test "$(in_h "$zsh_bin" -c 'print -r -- $CC')" = /usr/bin/clang
    assert "non-interactive zsh keeps ~/.local/bin first after the hook" \
        test "$(in_h "$zsh_bin" -c 'print -r -- $path[1]')" = "$h/.local/bin"
    login_path=$(in_h "$zsh_bin" -lc 'print -rl -- $path' 2>/dev/null)
    assert "login zsh keeps ~/.local/bin ahead of /usr/bin after path_helper" \
        test "$(printf '%s\n' "$login_path" | sed -n 1p)" = "$h/.local/bin"
    assert_not "the work environment references no Nix path" grep -rqE '/nix/|nix-profile|hm-session' "$root/work"
    assert "interactive zsh sources the employer's ~/.zshrc" \
        test "$(in_h TERM=dumb "$zsh_bin" -ic 'print -r -- ${EMPLOYER_RC_TEST-}' 2>/dev/null)" = 1
fi

# Every environment, smoreswork included, takes gh from mise.
h=$(new_home work-tools)
mkdir -p "$h/.config"
ln -s "$root/global" "$h/.config/mise"
current_tools() {
    (cd / && in_h MISE_ENV="$1" "$mise_bin" ls --current 2>/dev/null | awk '{print $1}')
}
assert "the base tool set includes gh" grep -qx gh <<<"$(current_tools "")"
assert "the work environment takes gh from mise" grep -qx gh <<<"$(current_tools desktop,work)"

# --- work identity: work everywhere ------------------------------------------

h=$(new_home work-identity)
assert "work identity apply exits 0" run_mise "$h" desktop,work dot apply
mkrepo "$h/Blitzy/svc" https://github.com/blitzy-ai/svc.git
mkrepo "$h/scratch"
mkrepo "$h/Blitzy/old" git@github.com:blitzy-platform/old.git
assert "an old work ssh remote is fetched over https" \
    test "$(url_of "$h/Blitzy/old")" = https://github.com/blitzy-platform/old.git
for repo in "$h/Blitzy/svc" "$h/scratch"; do
    assert "$(basename "$repo") commits as the work identity" test "$(gitcfg "$repo" user.email)" = smohr@blitzy.com
done
assert "the work name is hardcoded" test "$(gitcfg "$h/scratch" user.name)" = "Sam Mohr"
assert "work commits are not signed" test -z "$(gitcfg "$h/scratch" commit.gpgsign)"
assert "the work flow is pr" test "$(gitcfg "$h/scratch" smores.flow)" = pr
assert "the work machine has no git get" test -z "$(gitcfg "$h/scratch" alias.get)"
assert "work GitHub remotes stay on https" \
    test "$(url_of "$h/Blitzy/svc")" = https://github.com/blitzy-ai/svc.git
assert_not "the work SSH config has no github.com entry" \
    grep -qi '^identityagent ' <<<"$(in_h ssh -F "$h/.ssh/config" -G github.com 2>/dev/null)"

# mise reports an entry whose source is missing, or one it cannot apply, as a
# warning and exits 0.
assert_not "every dotfile source exists" grep -E 'matched no files|ignoring entry' "$tmp/mise.log"

# --- dotfile state from a checkout at another path ---------------------------

# A moved checkout leaves state keyed by its old source path, and prune reads
# that state: a record colliding with a live link made --prune-dotfiles delete
# the link and the next bootstrap recreate it. The pre-dotfiles hook drops the
# record before the apply, so prune never sees it.
h6=$(new_home stale)
state=$h6/.local/state/mise/dotfiles
assert "the first dotfiles bootstrap applies" \
    run_mise "$h6" "" bootstrap --only dotfiles
mkdir -p "$state"
cat >"$state/stale.toml" <<EOF
version = 1
source = "$h6/old/home/.config/gh"
target = "$h6/.config/gh"

[[links]]
source = "$h6/old/home/.config/gh/config.yml"
target = "$h6/.config/gh/config.yml"
EOF
assert "the bootstrap after a moved checkout exits 0" \
    run_mise "$h6" "" bootstrap --only dotfiles --prune-dotfiles
assert "state from the old checkout path is dropped" test ! -e "$state/stale.toml"
assert "the prune leaves the live link alone" links_into_repo "$h6/.config/gh/config.yml"

finish
