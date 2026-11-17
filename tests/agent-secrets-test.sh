#!/usr/bin/env bash
# Behavioural tests for the SOPS agent provider-key materialization, with fake sops.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }

home=$tmp/home
mkdir -p "$home/.config/sops" "$tmp/bin"
: >"$home/.config/sops/keys.age"
printf 'encrypted\n' >"$tmp/cipher.yaml"

cat >"$tmp/bin/sops" <<'EOF'
#!/bin/sh
[ "${FAKE_SOPS_FAIL:-}" = 1 ] && exit 1
printf 'NEURALWATT_API_KEY=nw-test\nTINYFISH_API_KEY=tf-test\nEXTRA_KEY=nope\n'
EOF
chmod +x "$tmp/bin/sops"

run() {
    env -i HOME="$home" PATH="$tmp/bin:/usr/bin:/bin" FAKE_SOPS_FAIL="${FAKE_SOPS_FAIL:-}" \
        DOTFILES_AGENT_SECRETS="$tmp/cipher.yaml" \
        sh "$root/scripts/agent-secrets.sh"
}

if run; then ok "decrypt exits 0"; else no "decrypt exits 0"; fi
secrets=$home/.config/secrets.env
if [ -f "$secrets" ] && grep -qx 'NEURALWATT_API_KEY=nw-test' "$secrets" \
        && grep -qx 'TINYFISH_API_KEY=tf-test' "$secrets"; then
    ok "the provider keys are written"
else
    no "the provider keys are written"
fi
if [ "$(stat -c %a "$secrets" 2>/dev/null || stat -f %Lp "$secrets")" = 600 ]; then
    ok "secrets.env is mode 600"
else
    no "secrets.env is mode 600"
fi
if grep -q 'EXTRA_KEY' "$secrets"; then
    no "keys other than the two providers are dropped"
else
    ok "keys other than the two providers are dropped"
fi

printf 'old\n' >"$secrets"
printf 'changed\n' >"$tmp/cipher.yaml"
if FAKE_SOPS_FAIL=1 run 2>/dev/null; then
    no "a failed decrypt exits nonzero"
else
    ok "a failed decrypt exits nonzero"
fi
if grep -qx 'old' "$secrets"; then
    ok "a failed decrypt keeps the existing file"
else
    no "a failed decrypt keeps the existing file"
fi

rm "$home/.config/sops/keys.age"
printf 'missing\n' >"$secrets"
run
if grep -qx 'missing' "$secrets"; then
    ok "a machine without the age identity is left alone"
else
    no "a machine without the age identity is left alone"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
