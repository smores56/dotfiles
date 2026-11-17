#!/usr/bin/env bash
# Behavioural tests for the combined SOPS secrets file, with fake sops/gh.
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
printf 'encrypted\n' >"$tmp/secrets.yaml"

cat >"$tmp/bin/sops" <<'EOF'
#!/bin/sh
printf 'sops\n' >>"$SECRETS_LOG"
printf 'NEURALWATT_API_KEY=%s\n' "${FAKE_NEURALWATT-nw-test}"
printf 'TINYFISH_API_KEY=%s\n' "${FAKE_TINYFISH-tf-test}"
[ -n "${FAKE_PAT-ghp_test}" ] && printf 'GITHUB_PERSONAL_PAT=%s\n' "$FAKE_PAT"
exit 0
EOF

cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$SECRETS_LOG"
case $1 in
    auth)
        case $2 in
            login) cat >"$GH_LOGIN" ;;
        esac ;;
esac
EOF
chmod +x "$tmp/bin/sops" "$tmp/bin/gh"

run() {
    env -i HOME="$home" PATH="$tmp/bin:/usr/bin:/bin" \
        SECRETS_LOG="$tmp/log" GH_LOGIN="$tmp/login" \
        FAKE_NEURALWATT="${FAKE_NEURALWATT-nw-test}" \
        FAKE_TINYFISH="${FAKE_TINYFISH-tf-test}" \
        FAKE_PAT="${FAKE_PAT-ghp_test}" \
        DOTFILES_SECRETS="$tmp/secrets.yaml" \
        sh "$root/scripts/secrets.sh"
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
if [ -f "$tmp/login" ] && [ "$(cat "$tmp/login")" = ghp_test ]; then
    ok "the PAT reaches gh on stdin"
else
    no "the PAT reaches gh on stdin"
fi

run
if [ "$(grep -c '^sops$' "$tmp/log")" -eq 1 ]; then
    ok "an unchanged file skips the second decrypt"
else
    no "an unchanged file skips the second decrypt"
fi

printf 'changed\n' >"$tmp/secrets.yaml"
run
if [ "$(grep -c '^sops$' "$tmp/log")" -eq 2 ]; then
    ok "a changed file decrypts again"
else
    no "a changed file decrypts again"
fi

printf 'old\n' >"$secrets"
printf 'changed2\n' >"$tmp/secrets.yaml"
if FAKE_NEURALWATT='' run 2>/dev/null; then
    no "missing provider keys fail"
else
    ok "missing provider keys fail"
fi
if grep -qx 'old' "$secrets"; then
    ok "missing provider keys keep the existing file"
else
    no "missing provider keys keep the existing file"
fi

printf 'changed3\n' >"$tmp/secrets.yaml"
printf 'auth\n' >"$tmp/log"
FAKE_PAT='' run >/dev/null 2>&1
if grep -q 'auth login' "$tmp/log"; then
    no "an empty PAT skips gh auth"
else
    ok "an empty PAT skips gh auth"
fi

rm "$home/.config/sops/keys.age"
printf 'auth\n' >"$tmp/log"
run
if grep -q 'auth login' "$tmp/log"; then
    no "a machine without the age identity is left alone"
else
    ok "a machine without the age identity is left alone"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
