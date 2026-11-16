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

h=$tmp/home
bin=$tmp/bin
mkdir -p "$h/.local/state/nix/profiles/home-manager-7-link" "$bin" "$h/.config/helix"
ln -s home-manager-7-link "$h/.local/state/nix/profiles/home-manager"
cat >"$h/.local/state/nix/profiles/home-manager-7-link/activate" <<'A'
#!/bin/sh
echo activated >"$HOME/activated"
A
chmod +x "$h/.local/state/nix/profiles/home-manager-7-link/activate"
ln -s "$mise_bin" "$bin/mise"
# home-manager still owns helix: a link into the Nix store.
ln -s /nix/store/fake-hm-files/helix-config.toml "$h/.config/helix/config.toml"

stub_hm() {  # stub_hm keep|drop: what the stub switch does to helix's link
    cat >"$bin/home-manager" <<S
#!/bin/sh
echo "\$*" >>"\$HOME/hm.log"
[ "$1" = drop ] && rm -f "\$HOME/.config/helix/config.toml"
exit 0
S
    chmod +x "$bin/home-manager"
}

hand() {
    env -i HOME="$h" PATH="$bin:/usr/bin:/bin" TERM=dumb DOTFILES="$root" NIX_CONFIG=/nowhere \
        MISE_TRUSTED_CONFIG_PATHS="$root" MISE_YES=1 sh "$root/scripts/handoff.sh" "$@"
}

hand --dry-run apply helix >"$tmp/dry.log" 2>&1
assert "a dry run prints the switch" grep -q 'would run: home-manager switch --flake /nowhere#sam@smoreswork' "$tmp/dry.log"
assert "a dry run prints the apply" grep -q 'would run: mise .* dot apply ~/.config/helix' "$tmp/dry.log"
assert_not "a dry run switches nothing" test -e "$h/hm.log"

stub_hm keep
assert_not "apply refuses while home-manager still writes the piece" hand apply helix
assert "the refusal leaves home-manager's link alone" test -L "$h/.config/helix/config.toml"

stub_hm drop
if hand apply helix >"$tmp/apply.log" 2>&1; then ok "apply succeeds once the switch drops the link"; else no "apply succeeds once the switch drops the link"; sed 's/^/     /' "$tmp/apply.log" >&2; fi
assert "helix now links into the checkout" bash -c "readlink '$h/.config/helix/config.toml' | grep -q '^$root/'"
assert "the generation before the handoff is recorded" grep -qx home-manager-7-link "$h/.local/state/dotfiles-handoff/helix.before"

if hand rollback helix >"$tmp/rollback.log" 2>&1; then ok "rollback succeeds"; else no "rollback succeeds"; sed 's/^/     /' "$tmp/rollback.log" >&2; fi
assert_not "rollback removes the dotfiles link first" test -L "$h/.config/helix/config.toml"
assert "rollback re-activates the recorded generation" test -e "$h/activated"
assert_not "rollback forgets the record" test -e "$h/.local/state/dotfiles-handoff/helix.before"
assert_not "rollback without a record refuses" hand rollback helix

mkdir -p "$h/.config/zsh"; : >"$h/.config/zsh/.zcompdump-old"
hand apply zsh >"$tmp/zsh.log" 2>&1 || true
assert_not "the zsh handoff clears home-manager's completion dumps" test -e "$h/.config/zsh/.zcompdump-old"
assert_not "an unknown piece is refused" hand apply fish

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
