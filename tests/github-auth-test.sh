#!/usr/bin/env bash
# Behavioural tests for the optional SOPS-backed gh login, with fake sops/gh.
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
printf 'encrypted\n' >"$tmp/github.yaml"

cat >"$tmp/bin/sops" <<'EOF'
#!/bin/sh
printf 'sops\n' >>"$GH_LOG"
printf '%s\n' "${FAKE_TOKEN:-ghp_test}"
EOF

cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$GH_LOG"
case $1 in
    auth)
        case $2 in
            status) [ -f "$GH_LOGIN" ] ;;
            login) cat >"$GH_LOGIN" ;;
        esac ;;
esac
EOF
chmod +x "$tmp/bin/sops" "$tmp/bin/gh"

run() {
    env -i HOME="$home" PATH="$tmp/bin:/usr/bin:/bin" \
        GH_LOG="$tmp/log" GH_LOGIN="$tmp/login" FAKE_TOKEN="${FAKE_TOKEN:-ghp_test}" \
        DOTFILES_GITHUB_SECRETS="$tmp/github.yaml" \
        sh "$root/scripts/github-auth.sh"
}

if run; then ok "login exits 0"; else no "login exits 0"; fi
if [ -f "$tmp/login" ] && [ "$(cat "$tmp/login")" = ghp_test ]; then
    ok "the token reaches gh on stdin"
else
    no "the token reaches gh on stdin"
fi
if [ "$(grep -c '^sops$' "$tmp/log")" -eq 1 ]; then
    ok "the token is read once"
else
    no "the token is read once"
fi

run
if [ "$(grep -c 'auth login' "$tmp/log")" -eq 1 ]; then
    ok "an unchanged ciphertext and a valid login skip the re-login"
else
    no "an unchanged ciphertext and a valid login skip the re-login"
fi

printf 'changed\n' >"$tmp/github.yaml"
run
if [ "$(grep -c 'auth login' "$tmp/log")" -eq 2 ]; then
    ok "a changed ciphertext logs in again"
else
    no "a changed ciphertext logs in again"
fi

rm "$home/.config/sops/keys.age"
printf 'auth\n' >"$tmp/log"
run
if grep -q 'auth login' "$tmp/log"; then
    no "a machine without the age identity is left alone"
else
    ok "a machine without the age identity is left alone"
fi

rm "$tmp/github.yaml"
run
if grep -q 'auth login' "$tmp/log"; then
    no "a missing ciphertext is left alone"
else
    ok "a missing ciphertext is left alone"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
