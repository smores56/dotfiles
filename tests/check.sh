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

for script in "$root"/scripts/*.sh "$root"/tests/*.sh; do
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

# --- zsh

if command -v zsh >/dev/null 2>&1; then
    for zsh_file in "$root"/home/.zshenv "$root"/home/.config/zsh/.z* \
            "$root"/home/.config/zsh/conf.d/*.zsh; do
        [ -f "$zsh_file" ] || continue
        if zsh -n "$zsh_file" 2>"$tmp/err"; then
            ok "syntax $(rel "$zsh_file") (zsh)"
        else
            no "syntax $(rel "$zsh_file") (zsh)"
            sed 's/^/     /' "$tmp/err" >&2
        fi
    done
else
    skip "syntax home/.config/zsh (zsh not installed)"
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

for cfg in "$root"/mise.toml "$root"/mise.*.toml "$root"/global/*.toml "$root"/global/*.lock \
        "$root"/desktop/.aerospace.toml "$root"/maki/config/*.toml \
        "$root"/home/.config/helix/*.toml "$root"/home/.config/television/cable/*.toml; do
    [ -f "$cfg" ] && toml "$cfg"
done

# --- desktop packages and shell hand-off

flatpaks=$(sed -n 's/^"flatpak-user:\([^"]*\)".*/\1/p' "$root/mise.desktop.toml")
if [ "$(printf '%s\n' "$flatpaks" | grep -c .)" -eq 10 ]; then
    ok "the desktop environment declares all 10 user Flatpaks"
else
    no "the desktop environment must declare 10 user Flatpaks"
fi

if printf '%s\n' "$flatpaks" | grep -qvE '^[A-Za-z0-9_]+(\.[A-Za-z0-9_-]+)+$'; then
    no "every flatpak id looks like a reverse-DNS app id"
else
    ok "every flatpak id looks like a reverse-DNS app id"
fi

if grep -q 'flatpak-user:org.wezfurlong.wezterm' "$root/mise.desktop.toml"; then
    no "WezTerm must not come from Flathub; that build predates this GPU's Mesa"
else
    ok "WezTerm is not the abandoned Flathub build"
fi

kitty_conf="$root/desktop/.config/kitty/kitty.conf"
if [ -f "$kitty_conf" ] \
    && grep -q "^font_family family='Google Sans Code'" "$kitty_conf" \
    && grep -q '"~/.config/kitty"' "$root/mise.desktop.toml"; then
    ok "the Linux terminal is kitty from the image"
else
    no "the Linux terminal must be kitty from the image"
fi

if grep -qE 'flatpak-user:(com\.brave\.Browser|org\.kde\.dolphin)' "$root/mise.desktop.toml"; then
    no "Brave Origin and Dolphin must come from the image, not Flathub"
else
    ok "Brave Origin and Dolphin are not Flathub packages"
fi

if grep -q 'flatpak remote-add --user --if-not-exists flathub' "$root/mise.desktop.toml"; then
    ok "the pre-packages hook adds the user Flathub remote"
else
    no "the pre-packages hook must add the user Flathub remote"
fi

if grep -q '"~/.bash_profile/zsh"' "$root/mise.desktop.toml" \
        && grep -q 'BASH_EXECUTION_STRING' "$root/mise.desktop.toml"; then
    ok "the bash_profile block hands interactive logins to zsh only"
else
    no "the bash_profile block must exec zsh only without BASH_EXECUTION_STRING"
fi

if grep -qE '^MAKI_VERSION=v[0-9]+\.[0-9]+\.[0-9]+$' "$root/maki/pin.env" \
        && grep -qE '^MAKI_SHA256=[0-9a-f]{64}$' "$root/maki/pin.env" \
        && grep -qE '^MAKI_TARGET=[A-Za-z0-9_-]+$' "$root/maki/pin.env"; then
    ok "maki/pin.env pins version, target, and checksum"
else
    no "maki/pin.env must pin MAKI_VERSION, MAKI_TARGET, and a 64-hex MAKI_SHA256"
fi

if [ -e "$root/local.env" ]; then
    no "local.env is retired: identity is hardcoded in the templates"
else
    ok "local.env is retired: identity is hardcoded in the templates"
fi

if grep -rqE 'exec\(' "$root"/identity "$root"/desktop "$root"/home "$root"/mise*.toml 2>/dev/null; then
    no "no template or hook calls exec() (dotfile status would run it)"
else
    ok "no template or hook calls exec() (dotfile status would run it)"
fi

# --- layout

for required in \
    "$root/mise.toml" \
    "$root/global/config.toml" \
    "$root/global/mise.lock" \
    "$root/global/mise.desktop.lock" \
    "$root/scripts/install-mise.sh" \
    "$root/scripts/bootstrap-task.sh" \
    "$root/README.md" \
    "$root/docs/manual-steps.md" \
    "$root/identity/.gitconfig" \
    "$root/maki/config/init.lua" \
    "$root/maki/config/providers.toml" \
    "$root/maki/skills/sdlc/SKILL.md"; do
    if [ -f "$required" ] || [ -L "$required" ]; then
        ok "present $(rel "$required")"
    else
        no "missing $(rel "$required")"
    fi
done

if [ -e "$root/home/.config/mise" ]; then
    # `mise bootstrap --config-dir global` links ~/.config/mise to global/; a
    # second copy under home/ would drift from it.
    no "home/.config/mise must not exist (global/ is the global config)"
else
    ok "the global mise config lives only in global/"
fi

if grep -q 'https://mise.run' "$root/scripts/install-mise.sh" \
        && grep -q 'MISE_VERSION=' "$root/scripts/install-mise.sh" \
        && grep -q 'detect-envs.sh' "$root/scripts/install-mise.sh"; then
    ok "install-mise uses the official installer for the latest mise and infers the set"
else
    no "install-mise must use the official installer for the latest mise and infer the set"
fi

for removed in install.sh packages/mise.toml packages/flatpaks.txt scripts/bootstrap.sh; do
    if [ -e "$root/$removed" ]; then
        no "the retired installer piece $removed is gone"
    else
        ok "the retired installer piece $removed is gone"
    fi
done

# --- lockfiles cover every pinned tool on every platform it runs on

if python3 -c 'import tomllib' >/dev/null 2>&1; then
    if python3 - "$root/global" >"$tmp/lock.out" 2>&1 <<'PY'
import pathlib, sys, tomllib
root = pathlib.Path(sys.argv[1])
all_platforms = {"linux-x64", "linux-arm64", "macos-arm64"}
os_platforms = {"linux": {"linux-x64", "linux-arm64"}, "macos": {"macos-arm64"}}
missing = []
for config in sorted(root.glob("config*.toml")):
    env = config.stem.removeprefix("config").lstrip(".")
    lock_path = root / (f"mise.{env}.lock" if env else "mise.lock")
    tools = tomllib.loads(config.read_text()).get("tools", {})
    locked = tomllib.loads(lock_path.read_text()).get("tools", {}) if lock_path.exists() else {}
    for name, spec in tools.items():
        want = set().union(*(os_platforms[o] for o in spec["os"])) if isinstance(spec, dict) and "os" in spec else all_platforms
        pin = spec["version"] if isinstance(spec, dict) else spec
        entries = [e for e in locked.get(name, []) if e.get("version") == pin]
        if not entries:
            missing.append(f"{config.name}: {name} = {pin} is not in {lock_path.name} (stale lock?)")
            continue
        have = {p.removeprefix("platforms.") for e in entries for p, v in e.items()
                if p.startswith("platforms.") and isinstance(v, dict) and v.get("checksum")}
        # mise records only the version for pipx tools; the uv lock beside the
        # config pins the package and its dependencies by hash.
        if name.startswith("pipx:"):
            uv_lock = root / "locks" / name.replace(":", "-") / pin / "uv.lock"
            text = uv_lock.read_text() if uv_lock.exists() else ""
            if f'version = "{pin}"' not in text or "sha256:" not in text:
                missing.append(f"{config.name}: {name} = {pin} has no hashed uv lock at {uv_lock.relative_to(root)}")
            continue
        for platform in sorted(want - have):
            missing.append(f"{config.name}: {name} has no checksummed {platform} entry in {lock_path.name}")
print("\n".join(missing))
sys.exit(1 if missing else 0)
PY
    then
        ok "the global lockfiles cover every pinned tool on its platforms"
    else
        no "the global lockfiles cover every pinned tool on its platforms"
        sed 's/^/     /' "$tmp/lock.out" >&2
    fi
else
    skip "lockfile coverage (python3 tomllib missing)"
fi

# --- retired toolchains and services
#
# sdlc/ is vendored upstream source: its notify skill and fixtures still name
# the cluster bus and nix-config, which the dotfiles config no longer uses.

if grep -rInE 'chezmoi|ntfy' "$root" \
        --exclude-dir=.git --exclude-dir=.worktrees --exclude-dir=sdlc \
        --exclude=check.sh >/dev/null 2>&1; then
    no "no chezmoi or ntfy reference remains"
    grep -rInE 'chezmoi|ntfy' "$root" \
        --exclude-dir=.git --exclude-dir=.worktrees --exclude-dir=sdlc \
        --exclude=check.sh | sed 's/^/     /' >&2
else
    ok "no chezmoi or ntfy reference remains"
fi

# docs/manual-steps.md deliberately calls the old machine's key-backup before
# the disk is wiped. The smoreswork coexistence files (work/, the work env,
# the handoff script, and their tests) talk to the home-manager generation
# that still runs there. Those are the only allowed nix references.
if grep -rInE '\bnix\b|nixos|nixpkgs|nix-shell' "$root" \
        --exclude-dir=.git --exclude-dir=.worktrees --exclude-dir=sdlc \
        --exclude=check.sh \
        --exclude=manual-steps.md --exclude-dir=work --exclude=mise.work.toml \
        --exclude=handoff.sh --exclude=handoff-test.sh --exclude=bootstrap-test.sh >/dev/null 2>&1; then
    no "no nix reference remains outside docs/manual-steps.md"
    grep -rInE '\bnix\b|nixos|nixpkgs|nix-shell' "$root" \
        --exclude-dir=.git --exclude-dir=.worktrees --exclude-dir=sdlc \
        --exclude=check.sh \
        --exclude=manual-steps.md --exclude-dir=work --exclude=mise.work.toml \
        --exclude=handoff.sh --exclude=handoff-test.sh --exclude=bootstrap-test.sh | sed 's/^/     /' >&2
else
    ok "no nix reference remains outside docs/manual-steps.md"
fi

secret_pattern='BEGIN [A-Z ]*PRIVATE KEY|AGE-SECRET-KEY-[A-Z0-9]|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'
if grep -rInE "$secret_pattern" "$root/home" "$root/identity" "$root/desktop" \
        "$root/work" "$root/maki" "$root/global" "$root/scripts" "$root/tests" \
        "$root/.github" >/dev/null 2>&1; then
    no "secret material in a managed file"
else
    ok "no secret material in managed files"
fi

if grep -rE 'curl|wget' "$root/home/.zshenv" "$root/home/.config/zsh" >/dev/null 2>&1; then
    no "zsh startup downloads at shell start"
    grep -rnE 'curl|wget' "$root/home/.zshenv" "$root/home/.config/zsh" | sed 's/^/     /' >&2
else
    ok "no downloader in zsh startup"
fi

if grep -qE '^zstyle .:zim. disable-version-check yes$' "$root/home/.config/zsh/.zshrc" \
        && ! grep -q 'zimfw' "$root/home/.config/zsh/.zshrc"; then
    ok "zsh startup never runs zimfw or its version check"
else
    no "zsh startup must only source zim's init.zsh, with the version check disabled"
fi

if grep -vE '^\s*(#|$|_p=|unset |--)' "$root/home/.config/zsh/.zimrc" | grep -qvE '^zmodule \$_p/'; then
    no "every zim module is an external path cloned by [bootstrap.repos]"
else
    ok "every zim module is an external path cloned by [bootstrap.repos]"
fi

if grep -E '^"~/.local/share/zsh-plugins/' "$root/mise.toml" | grep -qvE 'ref = "[0-9a-f]{40}"( |,)'; then
    no "every zsh plugin repo is pinned to a full commit"
else
    ok "every zsh plugin repo is pinned to a full commit"
fi

# --- one checkout root, one instruction set

if grep -q 'root = /srv/git' "$root/identity/.config/git/machine.inc.tera" \
        && grep -q 'ROOT=${REPOS_ROOT:-/srv/git}' "$root/home/.local/bin/repos" \
        && grep -q '/srv/git' "$root/scripts/install-mise.sh" \
        && grep -q 'ghq = "1.12.0"' "$root/global/config.toml"; then
    ok "every personal checkout root is /srv/git, and ghq points there"
else
    no "repos, ghq.root, install-mise, and ghq must all use /srv/git"
fi

# shellcheck disable=SC2088 # matching a literal ~/ on purpose
if grep -rnE '~/repos|~/ghq' "$root/mise.toml" "$root/mise.identity.toml" \
        "$root/home/.local/bin/repos" "$root/maki/config/AGENTS.md" \
        "$root/home/.claude/CLAUDE.md" "$root/README.md" \
        "$root/docs/manual-steps.md" "$root/scripts/install-mise.sh" >/dev/null 2>&1; then
    no "no file still points at ~/repos or ~/ghq"
    # shellcheck disable=SC2088 # matching a literal ~/ on purpose
    grep -rnE '~/repos|~/ghq' "$root/mise.toml" "$root/mise.identity.toml" \
        "$root/home/.local/bin/repos" "$root/maki/config/AGENTS.md" \
        "$root/home/.claude/CLAUDE.md" "$root/README.md" \
        "$root/docs/manual-steps.md" "$root/scripts/install-mise.sh" | sed 's/^/     /' >&2
else
    ok "no file still points at ~/repos or ~/ghq"
fi

if grep -q 'name = "Sam Mohr"' "$root/identity/.config/git/machine.inc.tera" \
        && grep -q 'email = "sam@sammohr.dev"' "$root/identity/.config/git/machine.inc.tera" \
        && grep -q 'name = "Sam Mohr"' "$root/work/.config/git/machine.inc.tera" \
        && grep -q 'email = "smohr@blitzy.com"' "$root/work/.config/git/machine.inc.tera"; then
    ok "personal and work name and email are hardcoded in the templates"
else
    no "the templates must hardcode Sam Mohr and the two emails"
fi

if grep -qE '^\[vars\.' "$root"/mise*.toml; then
    no "there are no [vars]; every identity value is hardcoded"
    grep -nE '^\[vars\.' "$root"/mise*.toml | sed 's/^/     /' >&2
else
    ok "there are no [vars]; every identity value is hardcoded"
fi

if grep -q 'SDLC_REPO=smores56/sdlc' "$root/home/.config/zsh/.zshenv" \
        && grep -q 'SDLC_REPO=smohr-blitzy/sdlc' "$root/work/.config/zsh/env.d/work.zsh"; then
    ok "the SDLC registry follows the machine's GitHub account"
else
    no "personal and work SDLC registries must be hardcoded"
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

task=$root/scripts/bootstrap-task.sh
if [ -x "$root/sdlc/sdlc_issues.py" ] \
        && grep -q '"~/.local/bin/sdlc" = { source = "sdlc/sdlc_issues.py" }' "$root/mise.toml" \
        && ! grep -q 'sdlc.git' "$task"; then
    ok "the sdlc CLI is deployed from this checkout"
else
    no "the sdlc CLI must be deployed from sdlc/sdlc_issues.py, not a private clone"
fi

installer=$root/scripts/install-mise.sh
if grep -q -- '--from "$REPO_URL"' "$installer" \
        && ! grep -q '?ref=' "$installer" \
        && grep -q 'detect-envs.sh' "$installer"; then
    ok "install-mise tracks the default branch and infers the set"
else
    no "install-mise must track the default branch (no ref) and infer the set"
fi

if grep -q 'sdlc list' "$root/docs/manual-steps.md" \
        && grep -q 'sdlc/sdlc_issues.py' "$root/docs/manual-steps.md"; then
    ok "docs/manual-steps.md names the local sdlc CLI"
else
    no "docs/manual-steps.md must name the local sdlc CLI"
fi

for file in "$root/docs/manual-steps.md" "$root/README.md"; do
    if grep -qE '^[[:space:]]*sudo rpm-ostree install' "$file"; then
        no "the host is a bootc image; $(rel "$file") must not layer host packages"
    else
        ok "$(rel "$file") never layers host packages"
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
    "$root/desktop/.local/bin/wallpapers" 'desktoppr|Darwin'
forbid "wallpapers does not fall back to host rsync" \
    "$root/desktop/.local/bin/wallpapers" 'rsync'
require "rclone is a pinned desktop tool" "$root/global/config.desktop.toml" \
    'aqua:rclone/rclone'
forbid "the wallpapers unit does not claim to rotate what it cannot set" \
    "$root/desktop/.config/systemd/user/wallpapers.service" 'Rotate wallpapers'
forbid "dev's header does not claim unconditional agent forwarding" \
    "$root/home/.local/bin/dev" 'The SSH agent socket is forwarded'
require "dev's usage documents the opt-in agent" "$root/home/.local/bin/dev" \
    'DEV_SSH_AGENT'
require "README documents the opt-in agent" "$root/README.md" 'DEV_SSH_AGENT=1'
require "the repos picker changes directory" \
    "$root/home/.config/zsh/conf.d/30-pickers.zsh" "alias r='cd \"\$(tv repos)\"'"
require "the worktrees picker changes directory" \
    "$root/home/.config/zsh/conf.d/30-pickers.zsh" "alias w='cd \"\$(tv worktrees)\"'"
forbid "no fish residue in the check images" "$root/.github/workflows/check.yml" 'fish'
forbid "no fish residue in the repository Containerfile" "$root/Containerfile" 'fish'
forbid "no fish residue in the shared dev image" \
    "$root/home/.config/containers/Containerfile.dev" 'fish'
forbid "zellij does not start fish" "$root/home/.config/zellij/config.kdl" 'fish'
require "zellij follows the terminal palette" "$root/home/.config/zellij/config.kdl" 'theme "ansi"'
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

if grep -q '^maki() {' "$root/home/.config/zsh/conf.d/40-maki.zsh" 2>/dev/null \
        && ! grep -rlE '^\s*export (NEURALWATT|TINYFISH)_API_KEY' "$root/home" >/dev/null 2>&1; then
    ok "provider keys reach only the maki process, never an export"
else
    no "provider keys must be passed by the maki() launcher only, never exported"
fi

# --- documentation and CI

for stale in install.sh local.env scripts/bootstrap.sh packages/flatpaks.txt; do
    if grep -qF -- "$stale" "$root/README.md" "$root/docs/manual-steps.md"; then
        no "the docs still mention the retired $stale"
    else
        ok "the docs do not mention the retired $stale"
    fi
done

for needle in 'fedora:43' 'macos-14' 'ubuntu-24.04-arm' 'tests/apply-lane.sh' \
        'mise install --locked'; do
    if grep -qF -- "$needle" "$root/.github/workflows/check.yml"; then
        ok "CI declares $needle"
    else
        no "CI is missing $needle"
    fi
done

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
        markdown-oxide) pkg='github:Feel-ix-343/markdown-oxide' ;;
        basedpyright) pkg='pipx:basedpyright' ;;
        *)
            helix_missing="$helix_missing $server(no pin)"
            continue ;;
    esac
    grep -qF "\"$pkg\" = " "$root/global/config.toml" \
        || helix_missing="$helix_missing $server($pkg)"
done
for server in $(grep -E '^language-servers' "$helix_languages" \
        | sed -E 's/.*\[//; s/\].*//; s/[" ]//g' | tr ',' '\n'); do
    printf '%s\n' "$helix_servers" | grep -qx "$server" \
        || helix_missing="$helix_missing $server(undefined)"
done
if [ -z "$helix_missing" ]; then
    ok "every Helix language server is defined and pinned in global/config.toml"
else
    no "Helix references a language server that is not installed:$helix_missing"
fi

# --- behavioral tests

if command -v git >/dev/null 2>&1 && command -v bash >/dev/null 2>&1; then
    if bash "$root/tests/bootstrap-test.sh" >"$tmp/bootstrap.log" 2>&1; then
        if grep -q '^skip bootstrap tests' "$tmp/bootstrap.log"; then
            skip "behavioral tests (tests/bootstrap-test.sh: mise not installed)"
        else
            ok "behavioral tests (tests/bootstrap-test.sh)"
        fi
    else
        no "behavioral tests (tests/bootstrap-test.sh)"
        sed 's/^/     /' "$tmp/bootstrap.log" >&2
    fi
    if bash "$root/tests/shell-test.sh" >"$tmp/shell.log" 2>&1; then
        if grep -q '^skip shell tests' "$tmp/shell.log"; then
            skip "behavioral tests (tests/shell-test.sh: mise or zsh not installed)"
        else
            ok "behavioral tests (tests/shell-test.sh)"
        fi
    else
        no "behavioral tests (tests/shell-test.sh)"
        sed 's/^/     /' "$tmp/shell.log" >&2
    fi
    if bash "$root/tests/handoff-test.sh" >"$tmp/handoff.log" 2>&1; then
        if grep -q '^skip handoff tests' "$tmp/handoff.log"; then
            skip "behavioral tests (tests/handoff-test.sh: mise not installed)"
        else
            ok "behavioral tests (tests/handoff-test.sh)"
        fi
    else
        no "behavioral tests (tests/handoff-test.sh)"
        sed 's/^/     /' "$tmp/handoff.log" >&2
    fi
    if bash "$root/tests/cli.sh" >"$tmp/cli.log" 2>&1; then
        ok "behavioral tests (tests/cli.sh)"
    else
        no "behavioral tests (tests/cli.sh)"
        sed 's/^/     /' "$tmp/cli.log" >&2
    fi
    if bash "$root/tests/wallpapers-test.sh" >"$tmp/wallpapers.log" 2>&1; then
        ok "behavioral tests (tests/wallpapers-test.sh)"
    else
        no "behavioral tests (tests/wallpapers-test.sh)"
        sed 's/^/     /' "$tmp/wallpapers.log" >&2
    fi
    if bash "$root/tests/detect-envs-test.sh" >"$tmp/detect-envs.log" 2>&1; then
        ok "behavioral tests (tests/detect-envs-test.sh)"
    else
        no "behavioral tests (tests/detect-envs-test.sh)"
        sed 's/^/     /' "$tmp/detect-envs.log" >&2
    fi
    if bash "$root/tests/secrets-test.sh" >"$tmp/secrets.log" 2>&1; then
        ok "behavioral tests (tests/secrets-test.sh)"
    else
        no "behavioral tests (tests/secrets-test.sh)"
        sed 's/^/     /' "$tmp/secrets.log" >&2
    fi
else
    skip "behavioral tests (git or bash not installed)"
fi

if command -v python3 >/dev/null 2>&1; then
    if PYTHONPATH="$root/sdlc" python3 -m unittest discover -s "$root/sdlc/tests" \
            >"$tmp/sdlc.log" 2>&1; then
        ok "sdlc unit tests"
    else
        no "sdlc unit tests"
        sed 's/^/     /' "$tmp/sdlc.log" >&2
    fi
else
    skip "sdlc unit tests (python3 not installed)"
fi

# --- optional shellcheck

if $use_shellcheck; then
    if command -v shellcheck >/dev/null 2>&1; then
        for script in "$root"/home/.local/bin/* "$root"/work/.local/bin/* "$root"/desktop/.local/bin/* \
                "$root/dev" "$root/maki/bin/maki-session-resume"; do
            [ -f "$script" ] || continue
            # SC3043: `local` is not POSIX, but every real /bin/sh implements it.
            if shellcheck -s sh -S warning -e SC3043 "$script" >"$tmp/out" 2>&1; then
                ok "shellcheck $(rel "$script")"
            else
                no "shellcheck $(rel "$script")"
                sed 's/^/     /' "$tmp/out" >&2
            fi
        done
        for script in "$root"/scripts/*.sh "$root"/tests/*.sh; do
            [ -f "$script" ] || continue
            # The shebang picks the dialect; SC3043 as above for the sh ones.
            if shellcheck -S warning -e SC3043 "$script" >"$tmp/out" 2>&1; then
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
