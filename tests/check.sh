#!/bin/sh
# Checks the source tree: every script parses, every config loads, the guards
# hold, and the behavioural tests pass.
#
# usage: tests/check.sh [--shellcheck]
set -u
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

use_shellcheck=false
[ "${1:-}" = "--shellcheck" ] && use_shellcheck=true

skip() { printf 'skip %s\n' "$*"; }
rel() { printf '%s' "${1#"$root"/}"; }
has() { command -v "$1" >/dev/null 2>&1; }

# --- syntax

shell_scripts() {
    for script in "$root"/home/.config/shell/env.sh "$root"/work/.config/shell/env.d/*.sh \
            "$root"/home/.local/bin/* "$root"/desktop/.local/bin/* \
            "$root"/scripts/*.sh "$root"/tests/*.sh; do
        [ -f "$script" ] || continue
        case $(head -n 1 "$script") in
            *python*) ;;
            *bash*) printf 'bash %s\n' "$script" ;;
            *) printf 'sh %s\n' "$script" ;;
        esac
    done
}

shell_scripts >"$tmp/scripts"
while read -r dialect script; do
    assert "syntax $(rel "$script") ($dialect)" "$dialect" -n "$script"
done <"$tmp/scripts"

if has zsh; then
    assert "syntax home/.zshenv (zsh)" zsh -n "$root/home/.zshenv"
else
    skip "syntax home/.zshenv (zsh not installed)"
fi

if has fish; then
    for fish_file in "$root"/home/.config/fish/*.fish \
            "$root"/*/.config/fish/conf.d/*.fish "$root"/*/.config/fish/conf.d/*.fish.tera; do
        [ -f "$fish_file" ] && assert "syntax $(rel "$fish_file") (fish)" fish --no-config -n "$fish_file"
    done
else
    skip "syntax fish (fish not installed)"
fi

if python3 -c 'import tomllib' >/dev/null 2>&1; then
    has_tomllib=true
    for cfg in "$root"/mise.toml "$root"/mise.*.toml "$root"/mise.*.lock "$root"/global/*.toml "$root"/global/*.lock \
            "$root"/desktop/.config/aerospace/aerospace.toml "$root"/home/.config/maki/*.toml \
            "$root"/home/.config/helix/*.toml; do
        [ -f "$cfg" ] && assert "toml $(rel "$cfg")" \
            python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$cfg"
    done
else
    has_tomllib=false
    skip "toml and lockfile coverage (python3 tomllib missing)"
fi

# --- desktop and shells

assert_not "every flatpak id looks like a reverse-DNS app id" sh -c \
    "sed -n 's/^\"flatpak-user:\([^\"]*\)\".*/\1/p' '$root/mise.desktop.toml' \
        | grep -vE '^[A-Za-z0-9_]+(\.[A-Za-z0-9_-]+)+\$'"

for kitty_conf in "$root"/desktop/.config/kitty/linux.conf "$root"/desktop/.config/kitty/macos.conf; do
    assert "kitty starts fish through its mise shim ($(rel "$kitty_conf"))" \
        grep -qxF 'shell ${HOME}/.local/share/mise/shims/fish' "$kitty_conf"
done
assert "zellij starts fish" grep -qx 'default_shell "fish"' "$root/home/.config/zellij/config.kdl"

assert_not "zsh has no interactive config: no ZDOTDIR, zim, plugins, or conda zsh" sh -c \
    "[ -e '$root/home/.config/zsh' ] || grep -rnE 'zim|zsh-plugins|conda:zsh|ZDOTDIR' \
        '$root/mise.toml' '$root'/mise.*.toml '$root/global/config.toml' '$root/scripts'"

assert "maki/pin.env pins version, target, and checksum" sh -c \
    "grep -qE '^MAKI_VERSION=v[0-9]+\.[0-9]+\.[0-9]+\$' '$root/maki/pin.env' \
        && grep -qE '^MAKI_SHA256=[0-9a-f]{64}\$' '$root/maki/pin.env' \
        && grep -qE '^MAKI_TARGET=[A-Za-z0-9_-]+\$' '$root/maki/pin.env'"

# `mise dot status` renders templates and hooks, so an exec() there would run.
assert_not "no template or hook calls exec()" \
    grep -rnE 'exec\(' "$root"/identity "$root"/desktop "$root"/home "$root"/mise.toml "$root"/mise.*.toml

# `--config-dir global` links ~/.config/mise to global/; a copy under home/ would drift.
assert_not "the global mise config lives only in global/" test -e "$root/home/.config/mise"

# --- lockfiles cover every pinned tool on every platform it runs on

lock_coverage() {
    python3 - "$root/global" <<'PY'
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
        # `platforms` is this check's key, not mise's: a tool upstream does not
        # build for every architecture in its os list names what it publishes.
        if isinstance(spec, dict) and "platforms" in spec:
            want = set(spec["platforms"])
        elif isinstance(spec, dict) and "os" in spec:
            want = set().union(*(os_platforms[o] for o in spec["os"]))
        else:
            want = all_platforms
        pin = spec["version"] if isinstance(spec, dict) else spec
        entries = [e for e in locked.get(name, []) if e.get("version") == pin]
        if not entries:
            missing.append(f"{config.name}: {name} = {pin} is not in {lock_path.name} (stale lock?)")
            continue
        have = {p.removeprefix("platforms.") for e in entries for p, v in e.items()
                if p.startswith("platforms.") and isinstance(v, dict) and v.get("checksum")}
        # mise records only the version for pipx tools; a uv lock pins them by hash.
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
}
$has_tomllib && assert "the global lockfiles cover every pinned tool on its platforms" lock_coverage

# --- secrets and downloads

# Nothing here is a private key, stub or otherwise: the smortress key arrives
# from sops at mode 600 per machine, so a PEM or a PAT in the tree is a leak.
secret_pattern='BEGIN [A-Z ]*PRIVATE KEY|AGE-SECRET-KEY-[A-Z0-9]|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'
offenders=''
for hit in $(grep -rIlE "$secret_pattern" "$root/home" "$root/identity" "$root/desktop" \
        "$root/work" "$root/maki" "$root/global" "$root/scripts" "$root/tests" \
        "$root/.github" 2>/dev/null); do
    offenders="$offenders $hit"
done
expect "no secret material in managed files" "" "$offenders"

# Every ciphertext carries exactly the recipients its creation rule names: a
# stale updatekeys or a hand-added recipient is a silent extra reader.
assert "sops ciphertext recipients match .sops.yaml" python3 - "$root" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
want = set(re.findall(r"age1[0-9a-z]+", (root / ".sops.yaml").read_text()))
have = set(re.findall(r"recipient: (age1[0-9a-z]+)", (root / "sops.yaml").read_text()))
sys.exit(1 if want != have else 0)
PY

# The key is one file per machine, out of sops; nothing may ship a copy.
assert_not "the tree carries no smortress key" \
    sh -c "test -e '$root/identity/.ssh/id_smortress' || test -e '$root/home/.ssh/id_smortress'"

assert_not "every fish plugin repo is pinned to a full commit" sh -c \
    "grep -E '^\"~/.local/share/fish-plugins/' '$root/mise.toml' | grep -vE 'ref = \"[0-9a-f]{40}\"( |,)'"
assert_not "no downloader in fish startup or the shared env" \
    grep -rnE 'curl|wget' "$root/home/.config/fish" "$root/home/.config/shell"

# --- cross-file consistency

var_root=$(sed -n 's|^repos_root = "\(/[^"]*\)"$|\1|p' "$root/mise.identity.toml" | head -1)
boot_root=$(sed -n 's|^ROOT=${BOOTSTRAP_ROOT:-\(/[^}]*\)}$|\1|p' "$root/scripts/bootstrap.sh" | head -1)
link_root=$(sed -n 's|^checkout=${DOTFILES_CHECKOUT:-\(/srv/git\)/.*|\1|p' \
    "$root/scripts/link-dotfiles-checkout.sh" | head -1)
assert "the checkout root matches in repos_root, bootstrap, and the link script" \
    test -n "$var_root" -a "$var_root" = "$boot_root" -a "$var_root" = "$link_root"

assert "bootstrap and git get make the same clean-bare clone, on personal machines only" sh -c \
    "grep -qF 'git clone --bare -c remote.origin.fetch=' '$root/scripts/bootstrap.sh' \
        && grep -qF 'git clone --bare -c remote.origin.fetch=' '$root/identity/.config/git/machine.inc.tera' \
        && ! grep -q '{{ vars.repos_root }}' '$root/work/.config/git/machine.inc.tera'"

for doc in "$root/home/.claude/CLAUDE.md" "$root/home/.config/maki/AGENTS.md"; do
    assert "$(rel "$doc") tells agents to clone with git get" grep -qF '`git get <owner/repo>`' "$doc"
done

assert "the personal SDLC registry is hardcoded" \
    grep -q 'SDLC_REPO=smores56/sdlc' "$root/home/.config/shell/env.sh"
assert "the work SDLC registry is hardcoded" \
    grep -q 'SDLC_REPO=smohr-blitzy/sdlc' "$root/work/.config/shell/env.d/work.sh"

# One producer and one consumer: a rename on either side leaves the wrapper
# without a credential.
for side in "$root/scripts/secrets.sh" "$root/home/.local/bin/smortress-ssh"; do
    assert "$(rel "$side") names the Access token file and secret" sh -c \
        "grep -q 'cloudflare/access.env' '$side' && grep -q CLOUDFLARE_ACCESS_CLIENT_SECRET '$side'"
done

# --- Maki guards

assert "the TinyFish guard runs on every tool call" \
    grep -qF 'set_slot("tool.*.input"' "$root/home/.config/maki/init.lua"
assert "the TinyFish guard allows only search" \
    grep -qF 'ctx.tool ~= "tinyfish__search"' "$root/home/.config/maki/init.lua"
assert "the maki wrapper hands the keys to the maki process" \
    grep -qF 'TINYFISH_API_KEY=$tinyfish exec "$bin"' "$root/home/.local/bin/maki"
assert_not "no file exports a provider key" \
    grep -rnE '^\s*export (NEURALWATT|TINYFISH)_API_KEY' "$root/home"

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
        *) helix_missing="$helix_missing $server(no pin)"; continue ;;
    esac
    grep -qF "\"$pkg\" = " "$root/global/config.toml" || helix_missing="$helix_missing $server($pkg)"
done
for server in $(grep -E '^language-servers' "$helix_languages" \
        | sed -E 's/.*\[//; s/\].*//; s/[" ]//g' | tr ',' '\n'); do
    printf '%s\n' "$helix_servers" | grep -qx "$server" || helix_missing="$helix_missing $server(undefined)"
done
expect "every Helix language server is defined and pinned in global/config.toml" "" "$helix_missing"

# --- behavioural tests

if has git && has bash; then
    for test_script in "$root"/tests/*-test.sh; do
        name=$(rel "$test_script")
        if bash "$test_script" >"$tmp/test.log" 2>&1; then
            if grep -q '^skip all' "$tmp/test.log"; then
                skip "behavioral tests ($name: $(sed -n 's/^skip all (\(.*\))$/\1/p' "$tmp/test.log"))"
            else
                ok "behavioral tests ($name)"
            fi
        else
            no "behavioral tests ($name)"
            indent <"$tmp/test.log"
        fi
    done
else
    skip "behavioral tests (git or bash not installed)"
fi

if has python3; then
    assert "sdlc unit tests" python3 -m unittest discover -s "$root/sdlc/tests"
else
    skip "sdlc unit tests (python3 not installed)"
fi

# --- optional shellcheck

if $use_shellcheck; then
    if has shellcheck; then
        # SC3043: `local` is not POSIX, but every real /bin/sh implements it.
        while read -r dialect script; do
            assert "shellcheck $(rel "$script")" \
                sh -c 'cd "$1" && shellcheck -x -s "$2" -S warning -e SC3043 "$3"' sh "$root" "$dialect" "$script"
        done <"$tmp/scripts"
    else
        skip "shellcheck (not installed)"
    fi
fi

finish
