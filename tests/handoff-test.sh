#!/usr/bin/env bash
# Behavioral tests for scripts/handoff.sh with a stub home-manager: no real
# home-manager generation is switched or activated. Requires mise.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
mise_bin=${MISE_BIN:-$(command -v mise || true)}
[ -n "$mise_bin" ] || { printf 'skip handoff tests (mise not installed)\n'; exit 0; }

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
assert() { local d=$1; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else no "$d"; fi; }
assert_not() { local d=$1; shift; if "$@" >/dev/null 2>&1; then no "$d"; else ok "$d"; fi; }
store_link() { [ -L "$1" ] && case $(readlink "$1") in /nix/store/*) true ;; *) false ;; esac; }
repo_link() { [ -L "$1" ] && case $(readlink "$1") in "$root"/*) true ;; *) false ;; esac; }

h=$tmp/home
bin=$tmp/bin
profiles=$h/.local/state/nix/profiles
mkdir -p "$bin" "$profiles"
ln -s "$mise_bin" "$bin/mise"

# Two generations; each activate script just records that it ran.
for n in 7 8; do
    mkdir -p "$profiles/home-manager-$n-link"
    printf '#!/bin/sh\necho %s >"$HOME/activated"\n' "$n" >"$profiles/home-manager-$n-link/activate"
    chmod +x "$profiles/home-manager-$n-link/activate"
done
ln -s home-manager-7-link "$profiles/home-manager"

# What home-manager writes for each piece in this fixture: nix store links,
# including television's nested cable/ files.
hm_links() {  # hm_links make|drop <piece>
    local links
    case $2 in
        helix) links=".config/helix/config.toml" ;;
        television) links=".config/television/cable/repos.toml" ;;
    esac
    for l in $links; do
        if [ "$1" = make ]; then
            mkdir -p "$(dirname "$h/$l")"
            rm -f "$h/$l"
            ln -s "/nix/store/fake-hm-files/$l" "$h/$l"
        else
            store_link "$h/$l" && rm -f "$h/$l"
        fi
    done
    return 0
}

# The stub switch does whatever $h/hm.mode says: keep, drop <piece>, make <piece>.
cat >"$bin/home-manager" <<'S'
#!/bin/sh
echo "$*" >>"$HOME/hm.log"
set -- $(cat "$HOME/hm.mode" 2>/dev/null)
[ "${1:-keep}" = keep ] && exit 0
exec bash "$HOME/../hm-links.sh" "$@"
S
chmod +x "$bin/home-manager"
{ declare -f hm_links store_link; printf 'h=%q\nhm_links "$@"\n' "$h"; } >"$tmp/hm-links.sh"
mode() { printf '%s\n' "$*" >"$h/hm.mode"; }

hand() {
    env -i HOME="$h" PATH="$bin:/usr/bin:/bin" TERM=dumb DOTFILES="$root" NIX_CONFIG_DIR=/nowhere \
        HANDOFF_SKIP_SHELL_CHECK=1 HANDOFF_SKIP_ZIM=1 \
        MISE_TRUSTED_CONFIG_PATHS="$root" MISE_YES=1 sh "$root/scripts/handoff.sh" "$@"
}

hm_links make helix
hm_links make television

# --- dry run ---
hand --dry-run apply helix >"$tmp/dry.log" 2>&1
assert "a dry run prints the switch" grep -q 'would run: home-manager switch --flake /nowhere#sam@smoreswork' "$tmp/dry.log"
assert "a dry run reports where a real run would stop" grep -q 'a real run would stop here' "$tmp/dry.log"
assert_not "a dry run switches nothing" test -e "$h/hm.log"
mode drop helix
env -i HOME="$h" PATH="$bin:/usr/bin:/bin" TERM=dumb DOTFILES="$root" NIX_CONFIG_DIR=/nowhere \
    HANDOFF_SKIP_SHELL_CHECK=1 sh "$root/scripts/handoff.sh" --dry-run apply zsh >"$tmp/dry-zsh.log" 2>&1
assert "the zsh handoff builds zim after deploying" grep -q 'would run: sh .*/scripts/zim-build.sh' "$tmp/dry-zsh.log"
rm -f "$h/hm.log" "$h/hm.mode"
assert_not "a dry run writes no state" test -e "$h/.local/state/dotfiles-handoff"

# --- refusal, nested links, retries ---
mode keep
assert_not "apply refuses while home-manager still writes the piece" hand apply helix
assert "the refusal leaves home-manager's link alone" store_link "$h/.config/helix/config.toml"
assert_not "a nested home-manager link also blocks the handoff" hand apply television
assert "the nested link is untouched" store_link "$h/.config/television/cable/repos.toml"

ln -sfn home-manager-8-link "$profiles/home-manager"   # a retry after another switch
mode drop helix
if hand apply helix >"$tmp/apply.log" 2>&1; then ok "apply succeeds once the switch drops the link"; else no "apply succeeds once the switch drops the link"; sed 's/^/     /' "$tmp/apply.log" >&2; fi
assert "helix now links into the checkout" repo_link "$h/.config/helix/config.toml"
assert "a retried apply keeps the generation from the first attempt" \
    grep -qx home-manager-7-link "$h/.local/state/dotfiles-handoff/helix.before"
assert "applying twice is harmless" hand apply helix

# --- zsh: the work hooks must land ---
mode keep
if hand apply zsh >"$tmp/zsh.log" 2>&1; then ok "the zsh handoff succeeds"; else no "the zsh handoff succeeds"; sed 's/^/     /' "$tmp/zsh.log" >&2; fi
assert "the zsh handoff links the work environment hook" repo_link "$h/.config/zsh/env.d/work.zsh"
assert "the zsh handoff links the interactive work hook" repo_link "$h/.config/zsh/conf.d/90-work.zsh"

# --- rollback ---
assert_not "--previous refuses an older handoff" hand rollback --previous helix
mode make helix
if hand rollback helix >"$tmp/rollback.log" 2>&1; then ok "a plain rollback succeeds"; else no "a plain rollback succeeds"; sed 's/^/     /' "$tmp/rollback.log" >&2; fi
assert "home-manager owns helix again" store_link "$h/.config/helix/config.toml"
assert_not "the rollback forgets helix" test -e "$h/.local/state/dotfiles-handoff/helix.before"
mode keep
assert_not "a plain rollback fails when home-manager does not take the piece back" hand rollback zsh
rm -f "$h/activated"
if hand rollback --previous zsh >"$tmp/prev.log" 2>&1; then ok "--previous undoes the latest handoff"; else no "--previous undoes the latest handoff"; sed 's/^/     /' "$tmp/prev.log" >&2; fi
assert "--previous activates the recorded generation" grep -qx 8 "$h/activated"
assert_not "--previous removes the zsh dotfiles first" test -L "$h/.config/zsh/env.d/work.zsh"
assert_not "an unknown piece is refused" hand apply fish

# The login-shell guard reads the real account, so only its shape is tested:
# a Nix-profile login shell stops the zsh handoff before anything runs.
cat >"$bin/dscl" <<'D'
#!/bin/sh
echo "UserShell: $HOME/.nix-profile/bin/zsh"
D
cat >"$bin/getent" <<'G'
#!/bin/sh
echo "u:x:1:1::$HOME:$HOME/.nix-profile/bin/zsh"
G
chmod +x "$bin/dscl" "$bin/getent"
rm -f "$h/hm.log"
assert_not "a Nix-profile login shell stops the zsh handoff" \
    env -i HOME="$h" PATH="$bin:/usr/bin:/bin" TERM=dumb DOTFILES="$root" NIX_CONFIG_DIR=/nowhere \
    sh "$root/scripts/handoff.sh" apply zsh
assert_not "the guard stops before any switch" test -e "$h/hm.log"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
