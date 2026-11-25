#!/usr/bin/env bats
# Applies each environment into a throwaway HOME; no real $HOME is touched and
# no network is used.
load helpers

mise_bin=${MISE_BIN:-$(command -v mise || true)}
os=$(uname -s)

# A mise shim whose version is unset is on PATH but fails at exec. Treating it
# as installed turns one environment gap into a pile of misleading failures.
usable_shell() {  # usable_shell <shell>: print its path when it runs
    local bin
    bin=$(command -v "$1" 2>/dev/null) || return 1
    "$bin" -c ':' >/dev/null 2>&1 || return 1
    printf '%s\n' "$bin"
}

# The zsh each platform logs in with: macOS's own /bin/zsh reads /etc/zprofile
# (path_helper), which a Nix- or Homebrew-built zsh on PATH does not.
if [ "$os" = Darwin ] && [ -x /bin/zsh ]; then
    zsh_bin=/bin/zsh
else
    zsh_bin=$(usable_shell zsh || true)
fi

links_into_repo() { [ -L "$1" ] && case $(readlink -- "$1") in "$dotfiles_root"/*) true ;; *) false ;; esac; }

# run_mise <home> <env> <args...>: mise with a clean environment, trusting only
# this checkout, so no global or user config leaks into the case. The output is
# appended to $mise_log -- the fixture log inside setup_file, the test's own file
# everywhere else -- and the subshell keeps mise's status past tee.
run_mise() {
    local home=$1 env=$2 log=${mise_log:-$BATS_TEST_TMPDIR/mise.log}
    shift 2
    (
        set -o pipefail
        env -i HOME="$home" PATH=/usr/bin:/bin:/usr/sbin:/sbin TERM=dumb \
            MISE_ENV="$env" MISE_TRUSTED_CONFIG_PATHS="$dotfiles_root" MISE_YES=1 \
            "$mise_bin" -C "$dotfiles_root" "$@" 2>&1 | tee -a "$log"
    )
}

# use_home <fixture>: a private copy of a prepared HOME. The links into the
# checkout are absolute, so a copy stays valid; mise's dotfile state is dropped
# because it names the fixture's own paths, and a test that pruned or unapplied
# through it would delete the shared fixture's links.
use_home() {
    h=$BATS_TEST_TMPDIR/home
    cp -a "$BATS_FILE_TMPDIR/$1" "$h"
    rm -rf "$h/.local/state/mise/dotfiles"
}

in_h() { env -i HOME="$h" PATH=/usr/bin:/bin "$@"; }
# What git resolves per checkout is the contract, not the file text.
gitcfg() { in_h git -C "$1" config --get "$2"; }
url_of() { in_h git -C "$1" ls-remote --get-url origin; }
mkrepo() { mkdir -p "$1" && git init -q "$1" && { [ -z "${2:-}" ] || git -C "$1" remote add origin "$2"; }; }
proxy_of() { in_h ssh -F "$h/.ssh/config" -G "$1" 2>/dev/null | sed -n 's/^proxycommand //p'; }
hostname_of() { in_h ssh -F "$h/.ssh/config" -G "$1" 2>/dev/null | sed -n 's/^hostname //p'; }
current_tools() {
    (cd / && in_h MISE_ENV="$1" "$mise_bin" ls --current 2>/dev/null | awk '{print $1}')
}

# mise reports an entry whose source is missing, or one it cannot apply, as a
# warning and exits 0.
assert_no_mise_warnings() {
    run grep -E 'matched no files|ignoring entry' "$BATS_TEST_TMPDIR/mise.log"
    assert_failure
}

# build_fixture <fixture> <env>: applies once into $BATS_FILE_TMPDIR/<fixture>
# and records the status the "apply exits 0" tests assert. Applying each
# environment is the bulk of this suite's runtime, so the three that many tests
# read are built here instead of per test.
build_fixture() {
    local status=0
    mkdir -p "$BATS_FILE_TMPDIR/$1"
    run_mise "$BATS_FILE_TMPDIR/$1" "$2" dot apply >/dev/null || status=$?
    printf '%s\n' "$status" >"$BATS_FILE_TMPDIR/$1.status"
}

apply_status() { cat "$BATS_FILE_TMPDIR/$1.status"; }

setup_file() {
    [ -n "$mise_bin" ] || skip "mise not installed"
    # A plain assignment on purpose: these fixture applies log here, while a
    # test's own applies fall back to its own log.
    mise_log=$BATS_FILE_TMPDIR/mise.log
    : >"$mise_log"

    # Claude's own settings arrive first, so the merge has something to keep.
    h=$BATS_FILE_TMPDIR/base-home
    mkdir -p "$h/.claude"
    printf '{\n  "theme": "dark",\n  "autoMemoryEnabled": false\n}\n' >"$h/.claude/settings.json"
    build_fixture base-home ""

    h=$BATS_FILE_TMPDIR/identity-home
    mkdir -p "$h/.ssh"
    build_fixture identity-home identity

    build_fixture desktop-home desktop

    # The employer's rc file exists before the work apply, which must leave it
    # alone. The work identity applies the same environments to the same kind of
    # home, so one fixture serves both.
    h=$BATS_FILE_TMPDIR/work-home
    mkdir -p "$h"
    printf 'export EMPLOYER_RC_TEST=1\n' >"$h/.zshrc"
    build_fixture work-home desktop,work
}

# --- base environment --------------------------------------------------------

@test "the base environment applies and merges Claude's settings" {
    h=$BATS_TEST_TMPDIR/home
    mkdir -p "$h/.claude"
    printf '{\n  "theme": "dark",\n  "autoMemoryEnabled": false\n}\n' >"$h/.claude/settings.json"
    run run_mise "$h" "" dot apply
    assert_success
    run python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["autoMemoryEnabled"])' \
        "$h/.claude/settings.json"
    assert_output "True"
    run grep -q '"theme": "dark"' "$h/.claude/settings.json"
    assert_success
    assert_no_mise_warnings
}

@test "base links the checkout into the home" {
    use_home base-home
    run links_into_repo "$h/.zshenv"
    assert_success
    run links_into_repo "$h/.config/shell/env.sh"
    assert_success
    run links_into_repo "$h/.config/fish/config.fish"
    assert_success
    run links_into_repo "$h/.config/fish/conf.d/20-abbreviations.fish"
    assert_success
    run links_into_repo "$h/.config/helix/config.toml"
    assert_success
    run links_into_repo "$h/.config/helix/languages.toml"
    assert_success
    run links_into_repo "$h/.config/zellij/config.kdl"
    assert_success
    run links_into_repo "$h/.config/zellij/themes/ansi.kdl"
    assert_success
    run links_into_repo "$h/.config/yazi/yazi.toml"
    assert_success
    run links_into_repo "$h/.config/gh/config.yml"
    assert_success
    run links_into_repo "$h/.config/sdlc/gh-dash.yml"
    assert_success
    run links_into_repo "$h/.local/bin/gh-sdlc"
    assert_success
    # gh only discovers extensions under its data dir, so this is its own entry.
    run links_into_repo "$h/.local/share/gh/extensions/gh-sdlc/gh-sdlc"
    assert_success
    run links_into_repo "$h/.local/bin/sops-age-key"
    assert_success
    run links_into_repo "$h/.local/bin/maki"
    assert_success
    run links_into_repo "$h/.config/maki/init.lua"
    assert_success
    run links_into_repo "$h/.config/maki/mcp.toml"
    assert_success
    run links_into_repo "$h/.config/maki/plugin.toml"
    assert_success
    run links_into_repo "$h/.config/maki/permissions.toml"
    assert_success
    run links_into_repo "$h/.agents/skills/sdlc/SKILL.md"
    assert_success
    run links_into_repo "$h/.claude/CLAUDE.md"
    assert_success
    run links_into_repo "$h/.claude/agents/Explore.md"
    assert_success
    run links_into_repo "$h/.claude/skills/sdlc/SKILL.md"
    assert_success
    run test -x "$h/.local/bin/gh-sdlc"
    assert_success
}

@test "base links lazygit where the platform's lazygit reads it" {
    use_home base-home
    if [ "$os" = Darwin ]; then
        run links_into_repo "$h/Library/Application Support/lazygit/config.yml"
        assert_success
    else
        run links_into_repo "$h/.config/lazygit/config.yml"
        assert_success
    fi
}

@test "CLAUDE.md imports the machine's work rules without the work-only ones" {
    use_home base-home
    run grep -qx '@~/.claude/work.md' "$h/.claude/CLAUDE.md"
    assert_success
    run grep -q Blitzy "$h/.claude/CLAUDE.md"
    assert_failure
    run grep -q 'No machine-specific rules' "$h/.claude/work.md"
    assert_success
}

@test "every skill reaches Claude Code" {
    use_home base-home
    for skill in "$dotfiles_root"/sdlc/skills/*/; do
        name=$(basename "$skill")
        run links_into_repo "$h/.claude/skills/$name/SKILL.md"
        assert_success
    done
}

@test "base leaves the files other environments own alone" {
    use_home base-home
    run test -e "$h/.config/git/config"
    assert_failure
    run test -e "$h/.ssh/config"
    assert_failure
    run test -e "$h/.ssh/smortress.conf"
    assert_failure
    run test -e "$h/.config/aerospace/aerospace.toml"
    assert_failure
    run test -e "$h/.local/bin/wallpapers"
    assert_failure
    run test -e "$h/.config/systemd/user/wallpapers.timer"
    assert_failure
    run test -e "$h/.config/mise"
    assert_failure
}

@test "gh clones and checks out over https" {
    use_home base-home
    run grep -qx 'git_protocol: https' "$h/.config/gh/config.yml"
    assert_success
}

@test "zsh puts the repo's paths first, login or not" {
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    use_home base-home
    run --separate-stderr in_h "$zsh_bin" -c 'print -rl -- $path'
    assert_equal "${lines[0]}" "$h/.local/bin"
    assert_equal "${lines[1]}" "$h/.local/share/mise/shims"
    run grep -qx /usr/bin <<<"$output"
    assert_success
    run --separate-stderr in_h "$zsh_bin" -lc 'print -rl -- $path'
    assert_equal "${lines[0]}" "$h/.local/bin"
    assert_equal "${lines[1]}" "$h/.local/share/mise/shims"
}

@test "every zsh exports GH_TOKEN from the token file" {
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    use_home base-home
    run in_h "$zsh_bin" -c 'print -r -- ${GH_TOKEN-unset}'
    assert_output "unset"
    printf 'tok-test\n' >"$h/.config/gh/token"
    run in_h "$zsh_bin" -c 'print -r -- $GH_TOKEN'
    assert_output "tok-test"
    printf 'tok-nonl' >"$h/.config/gh/token"
    run in_h "$zsh_bin" -c 'print -r -- ${GH_TOKEN-unset}'
    assert_output "tok-nonl"
}

@test "every zsh pages through bat" {
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    use_home base-home
    run in_h "$zsh_bin" -c 'print -r -- $PAGER:$BAT_THEME'
    assert_output "bat:ansi"
    run in_h "$zsh_bin" -c 'print -r -- $MANPAGER'
    assert_output "sh -c 'col -bx | bat -l man -p'"
}

@test "zsh keeps its default ZDOTDIR and drops an inherited one" {
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    use_home base-home
    run --separate-stderr in_h "$zsh_bin" -c 'print -r -- ${ZDOTDIR-unset}'
    assert_output "unset"
    run in_h ZDOTDIR=/old sh -c '. "$HOME/.config/shell/env.sh"; printf %s "${ZDOTDIR-unset}"'
    assert_output "unset"
}

# Sourcing the shared file again (a login after ~/.zshenv, a nested shell)
# moves its entries to the front instead of adding them twice.
# The middle PATH is what macOS path_helper leaves: system paths moved first.
@test "re-sourcing the env keeps one copy of each entry, in order" {
    use_home base-home
    run in_h sh -c \
        '. "$HOME/.config/shell/env.sh"; PATH=/usr/bin:/bin:$HOME/.local/share/mise/shims:$HOME/.local/bin; . "$HOME/.config/shell/env.sh"; printf %s "$PATH"'
    assert_output "$h/.local/bin:$h/.local/share/mise/shims:/usr/bin:/bin"
}

@test "login zsh gets the env from the ~/.zprofile block" {
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    use_home base-home
    run grep -q 'shell/env.sh' "$h/.zprofile"
    assert_success
}

@test "the shells still run while env.sh is not linked yet" {
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    use_home base-home
    mv "$h/.config/shell/env.sh" "$h/env.sh.away"
    run --separate-stderr in_h "$zsh_bin" -c 'print ok'
    assert_output "ok"
    run --separate-stderr in_h "$zsh_bin" -lc 'print ok'
    assert_output "ok"
    run --separate-stderr in_h bash -lc 'echo ok'
    assert_output "ok"
}

@test "bash reads the shared env in both login modes" {
    use_home base-home
    run --separate-stderr in_h TERM=dumb bash -lc 'printf %s "${PATH%%:*}:$PAGER"'
    assert_output "$h/.local/bin:bat"
    run --separate-stderr in_h TERM=dumb bash -ic 'printf %s "${PATH%%:*}:$PAGER"'
    assert_output "$h/.local/bin:bat"
}

@test "base unapply removes the links it created" {
    h=$BATS_TEST_TMPDIR/home
    mkdir -p "$h"
    run run_mise "$h" "" dot apply
    assert_success
    run run_mise "$h" "" dot unapply
    assert_success
    run test -L "$h/.config/helix/config.toml"
    assert_failure
    assert_no_mise_warnings
}

# --- files other installers own stay theirs ---------------------------------

@test "an existing ~/.zprofile does not block the apply" {
    h=$BATS_TEST_TMPDIR/home
    mkdir -p "$h"
    printf 'export PATH="$PATH:$HOME/.docker/bin"\n' >"$h/.zprofile"
    run run_mise "$h" "" dot apply
    assert_success
    run grep -qF '.docker/bin' "$h/.zprofile"
    assert_success
    run grep -q 'shell/env.sh' "$h/.zprofile"
    assert_success
    assert_no_mise_warnings
}

# --- conflicts are refused, never overwritten --------------------------------

@test "a real file in the way is kept" {
    h=$BATS_TEST_TMPDIR/home
    mkdir -p "$h/.config/helix"
    printf 'mine\n' >"$h/.config/helix/config.toml"
    # mise reports the conflict and exits non-zero; the file is the contract.
    run run_mise "$h" "" dot apply
    run grep -qx mine "$h/.config/helix/config.toml"
    assert_success
    run test -L "$h/.config/helix/config.toml"
    assert_failure
}

# --- identity environment ----------------------------------------------------

@test "identity links the checkout and renders the machine includes" {
    use_home identity-home
    run links_into_repo "$h/.config/git/config"
    assert_success
    run links_into_repo "$h/.ssh/config"
    assert_success
    run links_into_repo "$h/.ssh/smortress.conf"
    assert_success
    # identity is an overlay: the base links stay.
    run links_into_repo "$h/.config/helix/config.toml"
    assert_success
    run test -f "$h/.config/git/machine.inc"
    assert_success
    run test -f "$h/.config/git/work.inc"
    assert_success
}

# The route is one file under home/, included by both ssh configs: the tailnet is
# the only route, so ssh's own transport carries it and nothing proxies.
@test "the smortress route needs no proxy" {
    use_home identity-home
    assert_equal "$(proxy_of smortress)" ""
    assert_equal "$(hostname_of smortress)" smortress
    assert_equal "$(proxy_of ssh.sammohr.dev)" ""
}

@test "a personal checkout uses the personal identity and the local flow" {
    use_home identity-home
    mkrepo "$h/scratch"
    assert_equal "$(gitcfg "$h/scratch" user.name)" "Sam Mohr"
    assert_equal "$(gitcfg "$h/scratch" user.email)" sam@sammohr.dev
    assert_equal "$(gitcfg "$h/scratch" smores.flow)" local
    run grep -qF 'd=/srv/git/github.com/' <<<"$(gitcfg "$h/scratch" alias.get)"
    assert_success
    run test -z "$(gitcfg "$h/scratch" commit.gpgsign)"
    assert_success
}

@test "work remotes use the work identity and the pr flow" {
    use_home identity-home
    mkrepo "$h/wip/elsewhere" git@github.com:blitzy-ai/service.git
    mkrepo "$h/Blitzy/flat"
    mkrepo "$h/wip/https-work" https://github.com/blitzy-ai/other.git
    run grep -qF 'gitdir:/srv/git/github.com/blitzy-ai/' "$h/.config/git/machine.inc"
    assert_success
    assert_equal "$(gitcfg "$h/wip/elsewhere" user.email)" smohr@blitzy.com
    assert_equal "$(gitcfg "$h/wip/elsewhere" smores.flow)" pr
    assert_equal "$(gitcfg "$h/Blitzy/flat" user.email)" smohr@blitzy.com
    assert_equal "$(gitcfg "$h/wip/https-work" user.email)" smohr@blitzy.com
    run test -z "$(gitcfg "$h/wip/elsewhere" commit.gpgsign)"
    assert_success
}

@test "git and ssh remotes are fetched over https" {
    use_home identity-home
    mkrepo "$h/wip/elsewhere" git@github.com:blitzy-ai/service.git
    mkrepo "$h/wip/old-personal" ssh://git@github.com/smores56/old.git
    assert_equal "$(url_of "$h/wip/elsewhere")" https://github.com/blitzy-ai/service.git
    assert_equal "$(url_of "$h/wip/old-personal")" https://github.com/smores56/old.git
}

@test "identity applies without any SSH keys" {
    h=$BATS_TEST_TMPDIR/home
    mkdir -p "$h/.ssh"
    run run_mise "$h" identity dot apply
    assert_success
    run grep -q 'email = "smohr@blitzy.com"' "$h/.config/git/work.inc"
    assert_success
    assert_no_mise_warnings
}

# --- desktop environment -----------------------------------------------------

# The desktop apply is the fixture: applying it costs more than every other
# environment together, so it runs once and its status is the contract here.
@test "desktop apply exits 0" {
    assert_equal "$(apply_status desktop-home)" 0
}

@test "desktop keeps the base links and stays out of identity" {
    use_home desktop-home
    run links_into_repo "$h/.local/bin/maki"
    assert_success
    run test -e "$h/.config/git/config"
    assert_failure
}

# The emoji fallback is a download, not a dotfile: the bootstrap task owns it.
@test "the bootstrap installs and pins Noto Color Emoji" {
    run grep -qF 'install_noto_color_emoji' "$dotfiles_root/scripts/bootstrap-task.sh"
    assert_success
    run grep -qF '15671215ab769fdc7162a045d56fd7d7e477c51b04e6b3c761d914d8fdd6cc44' \
        "$dotfiles_root/scripts/bootstrap-task.sh"
    assert_success
}

@test "desktop links what the platform uses" {
    use_home desktop-home
    if [ "$os" = Darwin ]; then
        run links_into_repo "$h/.config/aerospace/aerospace.toml"
        assert_success
        run test -f "$h/Library/Fonts/GoogleSansCode-MONO-VF.ttf"
        assert_success
        run test -f "$h/Library/Fonts/GoogleSansCode-Italic-MONO-VF.ttf"
        assert_success
        run links_into_repo "$h/.config/kitty/macos.conf"
        assert_success
        run test -e "$h/.local/bin/wallpapers"
        assert_failure
        run test -e "$h/.config/systemd"
        assert_failure
        run test -e "$h/.local/share/fonts/GoogleSansCode-MONO-VF.ttf"
        assert_failure
    else
        run links_into_repo "$h/.local/bin/wallpapers"
        assert_success
        run links_into_repo "$h/.config/kitty/kitty.conf"
        assert_success
        run test -f "$h/.config/mimeapps.list"
        assert_success
        run links_into_repo "$h/.config/systemd/user/wallpapers.timer"
        assert_success
        # The sudo tap on smortress signs through this agent: without the unit
        # the user has no SSH_AUTH_SOCK to forward.
        run links_into_repo "$h/.config/systemd/user/ssh-agent.service"
        assert_success
        run grep -qF -- '-a %h/.local/state/ssh/agent.sock' "$h/.config/systemd/user/ssh-agent.service"
        assert_success
        # A resident handle loads without a touch, so the agent can come up
        # holding the credentials: without this every reboot leaves it empty and
        # every sudo afterwards is a password prompt.
        run grep -qF 'add-sudo-credential.sh' "$h/.config/systemd/user/ssh-agent.service"
        assert_success
        run grep -q 'SSH_AUTH_SOCK' "$h/.config/shell/env.d/10-ssh-agent.sh"
        assert_success
        run grep -q 'load_ssh_agent_linux' "$dotfiles_root/scripts/bootstrap-task.sh"
        assert_success
        run grep -q 'load_wallpapers_linux' "$dotfiles_root/scripts/bootstrap-task.sh"
        assert_success
        run grep -q 'systemctl --user start wallpapers.timer' \
            "$dotfiles_root/scripts/bootstrap-task.sh"
        assert_success
        run links_into_repo "$h/.local/share/fonts/GoogleSansCode-MONO-VF.ttf"
        assert_success
        run links_into_repo "$h/.local/share/fonts/GoogleSansCode-Italic-MONO-VF.ttf"
        assert_success
        run links_into_repo "$h/.config/fish/conf.d/80-desktop.fish"
        assert_success
        run test -e "$h/.config/aerospace/aerospace.toml"
        assert_failure
        run test -e "$h/Library/Fonts/GoogleSansCode-MONO-VF.ttf"
        assert_failure
    fi
}

# --- install-mise ------------------------------------------------------------

# A fresh root account has no ~/.local/bin on PATH, yet the bootstrap task's
# dependencies call `mise` by name, so install-mise must export it first.
@test "install-mise exports the checkout's bin for the bootstrap" {
    h=$BATS_TEST_TMPDIR/home
    local fake=$BATS_TEST_TMPDIR/fake-bin
    local log=$BATS_TEST_TMPDIR/install-mise.log
    mkdir -p "$h/.local/bin" "$fake"
    cat >"$h/.local/bin/mise" <<EOF
#!/bin/sh
printf 'PATH=%s\n' "\$PATH" >>"$log"
printf 'ARGS=%s\n' "\$*" >>"$log"
[ "\${1-}" = --version ] && printf 'mise stub\n'
exit 0
EOF
    chmod +x "$h/.local/bin/mise"
    printf '#!/bin/sh\nexit 0\n' >"$fake/curl"
    chmod +x "$fake/curl"
    run env -i HOME="$h" PATH="$fake:/usr/bin:/bin" DOTFILES_ENVS=identity \
        sh "$dotfiles_root/scripts/install-mise.sh"
    assert_success
    run grep -qxF "PATH=$h/.local/bin:$fake:/usr/bin:/bin" "$log"
    assert_success
    run grep -qF 'ARGS=bootstrap --from https://github.com/smores56/dotfiles.git' "$log"
    assert_success
}

# --- work environment --------------------------------------------------------

@test "work apply exits 0" {
    assert_equal "$(apply_status work-home)" 0
}

@test "work links the shared route and its own additions" {
    use_home work-home
    run links_into_repo "$h/.ssh/smortress.conf"
    assert_success
    run links_into_repo "$h/.config/shell/env.d/work.sh"
    assert_success
    run links_into_repo "$h/.config/fish/conf.d/90-work.fish"
    assert_success
    run grep -q 'This is a work host' "$h/.claude/work.md"
    assert_success
    # The employer's own rc file is a real file the env must not replace.
    run test -L "$h/.zshrc"
    assert_failure
}

# launchd starts at `/` and ssh starts the ProxyCommand outside any checkout, so
# neither can run a mise shim: the bootstrap writes wrappers next to them.
@test "the tailscaled agent launches the bootstrap's wrapper" {
    use_home work-home
    local plist=$h/Library/LaunchAgents/dev.sammohr.tailscaled.plist
    run grep -qF 'exec "$HOME/.local/bin/tailscaled"' "$plist"
    assert_success
    run grep -qF 'umask 077 &amp;&amp; mkdir -p "$HOME/.local/state/tailscale"' "$plist"
    assert_success
}

# The sudo tap on smortress asks the client's agent for a signature, so the Mac
# needs an agent that outlives one terminal: a LaunchAgent on a fixed socket.
# -D keeps it in the foreground: a forking agent exits 0, so KeepAlive respawns
# it every throttle interval and each respawn deletes the live socket.
# launchd has no ExecStartPost, so the Mac gets a script that runs the agent in
# the foreground and loads the credentials into it once the socket is bound --
# the same thing the Linux unit does with ExecStartPost.
@test "the ssh-agent LaunchAgent runs the serve script" {
    use_home work-home
    local agent=$h/Library/LaunchAgents/dev.sammohr.ssh-agent.plist
    run grep -qF 'exec "$HOME/.local/bin/ssh-agent-smortress"' "$agent"
    assert_success
    run grep -qF 'ssh-agent -D -a "$sock"' "$dotfiles_root/scripts/ssh-agent-serve.sh"
    assert_success
    run grep -qF 'add-sudo-credential.sh' "$dotfiles_root/scripts/ssh-agent-serve.sh"
    assert_success
    run grep -qF 'write_wrapper ssh-agent-smortress' "$dotfiles_root/scripts/bootstrap-task.sh"
    assert_success
    # The serve script owns the socket directory now: 0700 before ssh-agent
    # binds, and the stale socket removed before binding.
    run grep -qF 'umask 077' "$dotfiles_root/scripts/ssh-agent-serve.sh"
    assert_success
    run grep -qF 'rm -f "$sock"' "$dotfiles_root/scripts/ssh-agent-serve.sh"
    assert_success
}

# Apple's OpenSSH has no built-in FIDO middleware: without a provider, ssh-add
# refuses the sk handle with "Cannot load FIDO key ... without provider".
@test "the work shell exports the agent socket and Apple's provider" {
    use_home work-home
    run grep -q 'SSH_AUTH_SOCK=\$HOME/.local/state/ssh/agent.sock' \
        "$h/.config/shell/env.d/work.sh"
    assert_success
    run grep -q 'SSH_AUTH_SOCK' "$h/.config/fish/conf.d/90-work.fish"
    assert_success
    run grep -qF 'SSH_SK_PROVIDER=/usr/lib/ssh-keychain.dylib' \
        "$h/.config/shell/env.d/work.sh"
    assert_success
    run grep -qF 'SSH_SK_PROVIDER /usr/lib/ssh-keychain.dylib' \
        "$h/.config/fish/conf.d/90-work.fish"
    assert_success
}

@test "the bootstrap adds the sudo credentials through the provider" {
    run grep -qF 'SSH_SK_PROVIDER=/usr/lib/ssh-keychain.dylib' \
        "$dotfiles_root/scripts/add-sudo-credential.sh"
    assert_success
    # The agent is what signs the handle; launchd gives it no environment, so the
    # provider has to be set in the launcher or the tap silently costs a password.
    run grep -qF 'SSH_SK_PROVIDER=${SSH_SK_PROVIDER:-/usr/lib/ssh-keychain.dylib}' \
        "$dotfiles_root/scripts/ssh-agent-serve.sh"
    assert_success
    run grep -qF 'add-sudo-credential.sh' "$dotfiles_root/scripts/bootstrap-task.sh"
    assert_success
    # The image pins the sk keys that may sudo; without the comparison a spare
    # key's tap silently costs a password and a retired key stays authorized.
    run grep -qF 'check-sudo-pins.sh' "$dotfiles_root/scripts/bootstrap-task.sh"
    assert_success
}

@test "the work smortress route goes through the userspace tailscaled" {
    use_home work-home
    assert_equal "$(proxy_of smortress)" \
        '$HOME/.local/bin/tailscale --socket=$HOME/.local/state/tailscale/tailscaled.sock nc %h %p'
    # The file text is not the contract: `Include` is the first line of every
    # config that pulls smortress.conf in, and ssh keeps the first value it
    # obtains, so a later `Host *` can only win if that ordering breaks. Assert
    # what ssh resolves.
    run in_h ssh -F "$h/.ssh/config" -G smortress
    assert_equal "$(sed -n 's/^forwardagent //p' <<<"$output")" yes
    assert_equal "$(sed -n 's/^controlmaster //p' <<<"$output")" false
    assert_equal "$(hostname_of smortress)" smortress
    # `accept-new` pins whatever the corporate resolver answered, so the alias
    # keeps one known-hosts identity instead of one per answer.
    assert_equal "$(sed -n 's/^hostkeyalias //p' <<<"$output")" smortress
    assert_equal "$(proxy_of ssh.sammohr.dev)" ""
}

@test "non-interactive zsh on the work machine builds with Apple clang" {
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    use_home work-home
    run in_h "$zsh_bin" -c 'print -r -- $CC'
    assert_output "/usr/bin/clang"
    run in_h "$zsh_bin" -c 'print -r -- $path[1]'
    assert_output "$h/.local/bin"
    run --separate-stderr in_h "$zsh_bin" -lc 'print -rl -- $path'
    assert_equal "${lines[0]}" "$h/.local/bin"
}

@test "the work environment references no Nix path" {
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    run grep -rqE '/nix/|nix-profile|hm-session' "$dotfiles_root/work"
    assert_failure
}

@test "interactive zsh sources the employer's ~/.zshrc" {
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    use_home work-home
    run --separate-stderr in_h TERM=dumb "$zsh_bin" -ic 'print -r -- ${EMPLOYER_RC_TEST-}'
    assert_output "1"
}

# Every environment, smoreswork included, takes gh from mise.
@test "every environment takes gh from mise" {
    h=$BATS_TEST_TMPDIR/home
    mkdir -p "$h/.config"
    ln -s "$dotfiles_root/global" "$h/.config/mise"
    run grep -qx gh <<<"$(current_tools "")"
    assert_success
    run grep -qx gh <<<"$(current_tools desktop,work)"
    assert_success
}

# --- work identity: work everywhere ------------------------------------------

# The work identity applies the work environments, which the fixture above
# already did in a home of the same shape.
@test "work identity apply exits 0" {
    assert_equal "$(apply_status work-home)" 0
}

@test "every checkout on a work machine uses the work identity" {
    use_home work-home
    mkrepo "$h/Blitzy/svc" https://github.com/blitzy-ai/svc.git
    mkrepo "$h/scratch"
    mkrepo "$h/Blitzy/old" git@github.com:blitzy-platform/old.git
    assert_equal "$(url_of "$h/Blitzy/old")" https://github.com/blitzy-platform/old.git
    assert_equal "$(gitcfg "$h/Blitzy/svc" user.email)" smohr@blitzy.com
    assert_equal "$(gitcfg "$h/scratch" user.email)" smohr@blitzy.com
    assert_equal "$(gitcfg "$h/scratch" user.name)" "Sam Mohr"
    run test -z "$(gitcfg "$h/scratch" commit.gpgsign)"
    assert_success
    assert_equal "$(gitcfg "$h/scratch" smores.flow)" pr
    run test -z "$(gitcfg "$h/scratch" alias.get)"
    assert_success
    assert_equal "$(url_of "$h/Blitzy/svc")" https://github.com/blitzy-ai/svc.git
    run in_h ssh -F "$h/.ssh/config" -G github.com
    run grep -qi '^identityagent ' <<<"$output"
    assert_failure
}

@test "every dotfile source exists" {
    run grep -E 'matched no files|ignoring entry' "$BATS_FILE_TMPDIR/mise.log"
    assert_failure
}

# --- dotfile state from a checkout at another path ---------------------------

# A moved checkout leaves state keyed by its old source path, and prune reads
# that state: a record colliding with a live link made --prune-dotfiles delete
# the link and the next bootstrap recreate it. The pre-dotfiles hook drops the
# record before the apply, so prune never sees it.
@test "the bootstrap drops dotfile state from another checkout path" {
    h=$BATS_TEST_TMPDIR/home
    mkdir -p "$h"
    local state=$h/.local/state/mise/dotfiles
    run run_mise "$h" "" bootstrap --only dotfiles
    assert_success
    assert_no_mise_warnings
    mkdir -p "$state"
    cat >"$state/stale.toml" <<EOF
version = 1
source = "$h/old/home/.config/gh"
target = "$h/.config/gh"

[[links]]
source = "$h/old/home/.config/gh/config.yml"
target = "$h/.config/gh/config.yml"
EOF
    run run_mise "$h" "" bootstrap --only dotfiles --prune-dotfiles
    assert_success
    assert_no_mise_warnings
    run test -e "$state/stale.toml"
    assert_failure
    run links_into_repo "$h/.config/gh/config.yml"
    assert_success
}
