#!/bin/sh
# Checks the dotfiles source tree: every script parses, every config loads, the
# forbidden toolchains are gone, and the behavioral tests pass.
#
# usage: tests/check.sh [--shellcheck]
set -u

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
use_shellcheck=false
[ "${1:-}" = "--shellcheck" ] && use_shellcheck=true

checks=0
fails=0
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

ok() { checks=$((checks + 1)); printf 'ok   %s\n' "$*"; }
no() { checks=$((checks + 1)); fails=$((fails + 1)); printf 'FAIL %s\n' "$*" >&2; }
skip() { printf 'skip %s\n' "$*"; }
rel() { printf '%s' "${1#"$root"/}"; }

sh_syntax() {
    if sh -n "$1" 2>"$tmp/err"; then
        ok "syntax $(rel "$1") (sh)"
    else
        no "syntax $(rel "$1") (sh)"
        sed 's/^/     /' "$tmp/err" >&2
    fi
}

bash_syntax() {
    if bash -n "$1" 2>"$tmp/err"; then
        ok "syntax $(rel "$1") (bash)"
    else
        no "syntax $(rel "$1") (bash)"
        sed 's/^/     /' "$tmp/err" >&2
    fi
}

# --- shell scripts

for script in "$root"/home/.local/bin/* "$root"/maki/bin/maki-session-resume "$root/dev"; do
    [ -f "$script" ] || continue
    sh_syntax "$script"
done

for script in "$root/install.sh" "$root"/scripts/*.sh "$root"/tests/*.sh; do
    [ -f "$script" ] || continue
    bash_syntax "$script"
done

# --- python helper

if command -v python3 >/dev/null 2>&1; then
    if python3 -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' \
            "$root/maki/bin/maki-session-search" 2>"$tmp/err"; then
        ok "syntax maki/bin/maki-session-search (python3)"
    else
        no "syntax maki/bin/maki-session-search (python3)"
        sed 's/^/     /' "$tmp/err" >&2
    fi
else
    skip "syntax maki/bin/maki-session-search (python3 not installed)"
fi

# --- fish

if command -v fish >/dev/null 2>&1; then
    for fish_file in "$root"/home/.config/fish/config.fish "$root"/home/.config/fish/conf.d/*.fish \
            "$root"/home/.config/fish/functions/*.fish; do
        [ -f "$fish_file" ] || continue
        if fish -n "$fish_file" 2>"$tmp/err"; then
            ok "syntax $(rel "$fish_file") (fish)"
        else
            no "syntax $(rel "$fish_file") (fish)"
            sed 's/^/     /' "$tmp/err" >&2
        fi
    done
else
    skip "syntax home/.config/fish (fish not installed)"
fi

# --- TOML

toml() {
    if python3 -c 'import tomllib' >/dev/null 2>&1; then
        if python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1" 2>"$tmp/err"; then
            ok "toml $(rel "$1")"
        else
            no "toml $(rel "$1")"
            sed 's/^/     /' "$tmp/err" >&2
        fi
    else
        skip "toml $(rel "$1") (python3 tomllib missing)"
    fi
}

for cfg in "$root/packages/mise.toml" "$root"/maki/config/*.toml \
        "$root"/home/.config/helix/*.toml "$root"/home/.config/television/cable/*.toml; do
    [ -f "$cfg" ] && toml "$cfg"
done

# --- package lists and pins

if [ -s "$root/packages/flatpaks.txt" ]; then
    ok "packages/flatpaks.txt is not empty"
else
    no "packages/flatpaks.txt is empty"
fi

if grep -vE '^\s*(#|$)' "$root/packages/flatpaks.txt" \
        | grep -qvE '^[A-Za-z0-9_]+(\.[A-Za-z0-9_-]+)+$'; then
    no "every flatpak id looks like a reverse-DNS app id"
else
    ok "every flatpak id looks like a reverse-DNS app id"
fi

if grep -qE '^MAKI_VERSION=v[0-9]+\.[0-9]+\.[0-9]+$' "$root/maki/pin.env" \
        && grep -qE '^MAKI_SHA256=[0-9a-f]{64}$' "$root/maki/pin.env" \
        && grep -qE '^MAKI_TARGET=[A-Za-z0-9_-]+$' "$root/maki/pin.env"; then
    ok "maki/pin.env pins version, target, and checksum"
else
    no "maki/pin.env must pin MAKI_VERSION, MAKI_TARGET, and a 64-hex MAKI_SHA256"
fi

if grep -q '^local.env$' "$root/.gitignore"; then
    ok ".gitignore keeps local.env untracked"
else
    no ".gitignore must ignore local.env"
fi

if [ -f "$root/local.env.example" ]; then
    ok "local.env.example exists"
else
    no "local.env.example is missing"
fi

# --- layout

for required in \
    "$root/install.sh" \
    "$root/README.md" \
    "$root/docs/manual-steps.md" \
    "$root/home/.gitconfig" \
    "$root/packages/mise.toml" \
    "$root/maki/config/init.lua" \
    "$root/maki/config/providers.toml" \
    "$root/maki/skills/sdlc/SKILL.md"; do
    if [ -f "$required" ] || [ -L "$required" ]; then
        ok "present $(rel "$required")"
    else
        no "missing $(rel "$required")"
    fi
done

if [ -f "$root/home/.config/mise/config.toml" ] || [ -L "$root/home/.config/mise/config.toml" ]; then
    # Either a symlink to packages/mise.toml or no file at all: install.sh links
    # the pin explicitly. A real duplicate file would drift.
    no "home/.config/mise/config.toml must not duplicate packages/mise.toml"
else
    ok "the mise pin is linked from packages/, not duplicated"
fi

# --- retired toolchains and services

if grep -rInE 'chezmoi|ntfy' "$root" \
        --exclude-dir=.git --exclude-dir=.worktrees --exclude=check.sh >/dev/null 2>&1; then
    no "no chezmoi or ntfy reference remains"
    grep -rInE 'chezmoi|ntfy' "$root" \
        --exclude-dir=.git --exclude-dir=.worktrees --exclude=check.sh \
        | sed 's/^/     /' >&2
else
    ok "no chezmoi or ntfy reference remains"
fi

# docs/manual-steps.md deliberately calls the old machine's key-backup before
# the disk is wiped; that is the only allowed nix reference.
if grep -rInE '\bnix\b|nixos|nixpkgs|nix-shell' "$root" \
        --exclude-dir=.git --exclude-dir=.worktrees --exclude=check.sh \
        --exclude=manual-steps.md >/dev/null 2>&1; then
    no "no nix reference remains outside docs/manual-steps.md"
    grep -rInE '\bnix\b|nixos|nixpkgs|nix-shell' "$root" \
        --exclude-dir=.git --exclude-dir=.worktrees --exclude=check.sh \
        --exclude=manual-steps.md | sed 's/^/     /' >&2
else
    ok "no nix reference remains outside docs/manual-steps.md"
fi

secret_pattern='BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'
if grep -rInE "$secret_pattern" "$root/home" "$root/maki" "$root/packages" \
        "$root/scripts" "$root/install.sh" >/dev/null 2>&1; then
    no "secret material in a managed file"
else
    ok "no secret material in managed files"
fi

if grep -rE 'curl|wget' "$root/home/.config/fish" >/dev/null 2>&1; then
    no "fish startup downloads at shell start"
    grep -rnE 'curl|wget' "$root/home/.config/fish" | sed 's/^/     /' >&2
else
    ok "no downloader in fish startup"
fi

# --- one checkout root, one instruction set

if grep -rn 'ghq' "$root/install.sh" "$root/local.env.example" \
        "$root/home/.local/bin/repos" "$root/maki/config/AGENTS.md" >/dev/null 2>&1; then
    no "the checkout root is ~/repos everywhere, not the retired ~/ghq"
    grep -rn 'ghq' "$root/install.sh" "$root/local.env.example" \
        "$root/home/.local/bin/repos" "$root/maki/config/AGENTS.md" | sed 's/^/     /' >&2
else
    ok "the checkout root is ~/repos everywhere, not the retired ~/ghq"
fi

if grep -qE '`worktrees prune --apply`' "$root/maki/config/AGENTS.md"; then
    ok "AGENTS.md prunes with --apply"
else
    no "AGENTS.md must prune with 'worktrees prune --apply' (prune is a dry run by default)"
fi

if grep -qF 'worktrees prune              # dry run' "$root/README.md" \
        && ! grep -q 'one root step' "$root/README.md"; then
    ok "README describes the dry-run prune and the root steps truthfully"
else
    no "README must keep the dry-run prune note and drop the 'one root step' claim"
fi

# --- the tools the instructions require are actually installed

if grep -qE '^SDLC_REV=[0-9a-f]{40}$' "$root/scripts/bootstrap.sh" \
        && grep -q '^SDLC_UPSTREAM=git+ssh://git@github.com/smores56/sdlc$' \
            "$root/scripts/bootstrap.sh" \
        && grep -q 'uv tool install --force "\$pin"' "$root/scripts/bootstrap.sh"; then
    ok "bootstrap.sh installs the sdlc CLI at a pinned commit"
else
    no "bootstrap.sh must install sdlc with 'uv tool install' at a pinned commit"
fi

if grep -q 'uv tool install' "$root/docs/manual-steps.md" \
        && grep -q 'SDLC_REV' "$root/docs/manual-steps.md"; then
    ok "docs/manual-steps.md names the sdlc install and its pin"
else
    no "docs/manual-steps.md must name the sdlc install and its pin"
fi

for file in "$root/scripts/bootstrap.sh" "$root/docs/manual-steps.md" "$root/README.md"; do
    if grep -q 'rpm-ostree install tailscale rsync' "$file"; then
        ok "the host layer installs rsync in $(rel "$file")"
    else
        no "the host layer must install rsync in $(rel "$file")"
    fi
done

forbid() {  # forbid <desc> <path> <extended-regex>
    local desc=$1 path=$2 pattern=$3
    if grep -qE -- "$pattern" "$path" 2>/dev/null; then
        no "$desc"
        grep -nE -- "$pattern" "$path" | sed 's/^/     /' >&2
    else
        ok "$desc"
    fi
}

require() {  # require <desc> <path> <fixed-string>
    local desc=$1 path=$2 want=$3
    if grep -qF -- "$want" "$path" 2>/dev/null; then
        ok "$desc"
    else
        no "$desc"
    fi
}

forbid "wallpapers claims a COSMIC wallpaper setting it does not make" \
    "$root/home/.local/bin/wallpapers" 'desktoppr|Darwin'
forbid "the wallpapers unit does not claim to rotate what it cannot set" \
    "$root/home/.config/systemd/user/wallpapers.service" 'Rotate wallpapers'
forbid "dev's header does not claim unconditional agent forwarding" \
    "$root/home/.local/bin/dev" 'The SSH agent socket is forwarded'
require "dev's usage documents the opt-in agent" "$root/home/.local/bin/dev" \
    'DEV_SSH_AGENT'
require "README documents the opt-in agent" "$root/README.md" 'DEV_SSH_AGENT=1'
forbid "no undefined 'pick repos c' command" \
    "$root/home/.config/fish/conf.d/abbreviations.fish" "pick repos c'"
require "the repos picker changes directory" \
    "$root/home/.config/fish/conf.d/abbreviations.fish" "pick repos cd'"
forbid "no undefined 'pick worktrees c' command" \
    "$root/home/.config/fish/conf.d/abbreviations.fish" "pick worktrees c'"
require "the worktrees picker changes directory" \
    "$root/home/.config/fish/conf.d/abbreviations.fish" "pick worktrees cd'"
forbid "no zsh residue in the check images" "$root/.github/workflows/check.yml" 'zsh'
forbid "no zsh residue in the repository Containerfile" "$root/Containerfile" 'zsh'
forbid "no zsh residue in the shared dev image" \
    "$root/home/.config/containers/Containerfile.dev" 'zsh'
forbid "no TODO/TBD in the operator steps" "$root/docs/manual-steps.md" 'TODO|TBD'
forbid "no TODO/TBD in README" "$root/README.md" 'TODO|TBD'
forbid "the credentials step fetches keys instead of copying a missing file" \
    "$root/docs/manual-steps.md" 'media/<usb>/secrets.env'

if grep -q 'maki/pin.env' "$root/README.md" && grep -q 'pin bump' "$root/README.md"; then
    ok "README says a Maki update goes through a pin bump"
else
    no "README must say a Maki update goes through a pin bump"
fi

if grep -q 'bw unlock' "$root/docs/manual-steps.md" \
        && grep -q 'com.bitwarden.desktop' "$root/docs/manual-steps.md"; then
    ok "the credentials step fetches the keys from Bitwarden"
else
    no "the credentials step must fetch the keys from the Bitwarden CLI"
fi

if [ -f "$root/home/.config/fish/functions/maki.fish" ] \
        && [ ! -e "$root/home/.config/fish/conf.d/secrets.fish" ]; then
    ok "provider keys are exported by the maki launcher, not conf.d"
else
    no "provider keys must be exported by home/.config/fish/functions/maki.fish only"
fi

# --- helix: every configured language server is a pinned tool

helix_languages=$root/home/.config/helix/languages.toml
helix_servers=$(grep -oE '^\[language-server\.[a-z-]+' "$helix_languages" \
    | sed 's/.*\.//' | LC_ALL=C sort -u)
helix_missing=""
for server in $helix_servers; do
    case $server in
        ruff) pkg='aqua:astral-sh/ruff' ;;
        taplo) pkg='aqua:tamasfe/taplo' ;;
        marksman) pkg='aqua:artempyanykh/marksman' ;;
        *)
            helix_missing="$helix_missing $server(no pin)"
            continue ;;
    esac
    grep -qF "\"$pkg\" = " "$root/packages/mise.toml" \
        || helix_missing="$helix_missing $server($pkg)"
done
for server in $(grep -E '^language-servers' "$helix_languages" \
        | sed -E 's/.*\[//; s/\].*//; s/[" ,]//g'); do
    printf '%s\n' "$helix_servers" | grep -qx "$server" \
        || helix_missing="$helix_missing $server(undefined)"
done
if [ -z "$helix_missing" ]; then
    ok "every Helix language server is defined and pinned in packages/mise.toml"
else
    no "Helix references a language server that is not installed:$helix_missing"
fi

# --- behavioral tests

if command -v git >/dev/null 2>&1 && command -v bash >/dev/null 2>&1; then
    if bash "$root/tests/install-test.sh" >"$tmp/install.log" 2>&1; then
        ok "behavioral tests (tests/install-test.sh)"
    else
        no "behavioral tests (tests/install-test.sh)"
        sed 's/^/     /' "$tmp/install.log" >&2
    fi
    if bash "$root/tests/cli.sh" >"$tmp/cli.log" 2>&1; then
        ok "behavioral tests (tests/cli.sh)"
    else
        no "behavioral tests (tests/cli.sh)"
        sed 's/^/     /' "$tmp/cli.log" >&2
    fi
else
    skip "behavioral tests (git or bash not installed)"
fi

# --- optional shellcheck

if $use_shellcheck; then
    if command -v shellcheck >/dev/null 2>&1; then
        for script in "$root"/home/.local/bin/* "$root/dev" "$root/maki/bin/maki-session-resume"; do
            [ -f "$script" ] || continue
            # SC3043: `local` is not POSIX, but every real /bin/sh implements it.
            if shellcheck -s sh -S warning -e SC3043 "$script" >"$tmp/out" 2>&1; then
                ok "shellcheck $(rel "$script")"
            else
                no "shellcheck $(rel "$script")"
                sed 's/^/     /' "$tmp/out" >&2
            fi
        done
        for script in "$root/install.sh" "$root"/scripts/*.sh "$root"/tests/*.sh; do
            [ -f "$script" ] || continue
            if shellcheck -s bash -S warning "$script" >"$tmp/out" 2>&1; then
                ok "shellcheck $(rel "$script")"
            else
                no "shellcheck $(rel "$script")"
                sed 's/^/     /' "$tmp/out" >&2
            fi
        done
    else
        skip "shellcheck (not installed)"
    fi
fi

printf '\n%d checks, %d failed\n' "$checks" "$fails"
[ "$fails" -eq 0 ]
