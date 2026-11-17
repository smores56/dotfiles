#!/bin/sh
# Checks the dotfiles source tree: every script parses, every config loads, the
# guards hold, and the behavioral tests pass.
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

for script in "$root"/home/.local/bin/*; do
    [ -f "$script" ] || continue
    case $(head -n 1 "$script") in
        *python*) continue ;;
    esac
    sh_syntax "$script"
done

for script in "$root"/scripts/*.sh "$root"/tests/*.sh; do
    [ -f "$script" ] || continue
    bash_syntax "$script"
done

# --- python helper

if command -v python3 >/dev/null 2>&1; then
    if python3 -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' \
            "$root/home/.local/bin/maki-session-search" 2>"$tmp/err"; then
        ok "syntax home/.local/bin/maki-session-search (python3)"
    else
        no "syntax home/.local/bin/maki-session-search (python3)"
        sed 's/^/     /' "$tmp/err" >&2
    fi
else
    skip "syntax home/.local/bin/maki-session-search (python3 not installed)"
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
        "$root"/desktop/.aerospace.toml "$root"/home/.config/maki/*.toml \
        "$root"/home/.config/helix/*.toml "$root"/home/.config/television/cable/*.toml; do
    [ -f "$cfg" ] && toml "$cfg"
done

# --- desktop packages and login shell

flatpaks=$(sed -n 's/^"flatpak-user:\([^"]*\)".*/\1/p' "$root/mise.desktop.toml")

if printf '%s\n' "$flatpaks" | grep -qvE '^[A-Za-z0-9_]+(\.[A-Za-z0-9_-]+)+$'; then
    no "every flatpak id looks like a reverse-DNS app id"
else
    ok "every flatpak id looks like a reverse-DNS app id"
fi

kitty_conf="$root/desktop/.config/kitty/linux.conf"
if [ -f "$kitty_conf" ] && grep -qxF 'shell ${HOME}/.local/bin/zsh' "$kitty_conf"; then
    ok "kitty on Linux starts the mise zsh, not bash"
else
    no "kitty must start the mise zsh directly: it skips ~/.bash_profile"
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

if grep -rqE 'exec\(' "$root"/identity "$root"/desktop "$root"/home "$root"/mise*.toml 2>/dev/null; then
    no "no template or hook calls exec() (dotfile status would run it)"
else
    ok "no template or hook calls exec() (dotfile status would run it)"
fi

# --- layout

if [ -e "$root/home/.config/mise" ]; then
    # `mise bootstrap --config-dir global` links ~/.config/mise to global/; a
    # second copy under home/ would drift from it.
    no "home/.config/mise must not exist (global/ is the global config)"
else
    ok "the global mise config lives only in global/"
fi

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

# --- cross-file consistency

if grep -q 'ROOT=${REPOS_ROOT:-/srv/git}' "$root/home/.local/bin/repos" \
        && grep -q '/srv/git' "$root/scripts/install-mise.sh"; then
    ok "repos and install-mise agree on the /srv/git checkout root"
else
    no "repos and install-mise must both use /srv/git"
fi

if grep -q 'SDLC_REPO=smores56/sdlc' "$root/home/.config/zsh/.zshenv" \
        && grep -q 'SDLC_REPO=smohr-blitzy/sdlc' "$root/work/.config/zsh/env.d/work.zsh"; then
    ok "the SDLC registry follows the machine's GitHub account"
else
    no "personal and work SDLC registries must be hardcoded"
fi

# --- Maki guards

require() {  # require <desc> <path> <fixed-string>
    local desc=$1 path=$2 want=$3
    if grep -qF -- "$want" "$path" 2>/dev/null; then
        ok "$desc"
    else
        no "$desc"
    fi
}

require "the TinyFish guard runs on every tool call" \
    "$root/home/.config/maki/init.lua" 'set_slot("tool.*.input"'
require "the TinyFish guard allows only search" \
    "$root/home/.config/maki/init.lua" 'ctx.tool ~= "tinyfish__search"'

if grep -q '^maki() {' "$root/home/.config/zsh/conf.d/40-maki.zsh" 2>/dev/null \
        && ! grep -rlE '^\s*export (NEURALWATT|TINYFISH)_API_KEY' "$root/home" >/dev/null 2>&1; then
    ok "provider keys reach only the maki process, never an export"
else
    no "provider keys must be passed by the maki() launcher only, never exported"
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
        for script in "$root"/home/.local/bin/* "$root"/work/.local/bin/* "$root"/desktop/.local/bin/*; do
            [ -f "$script" ] || continue
            case $(head -n 1 "$script") in
                *python*) continue ;;
            esac
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
