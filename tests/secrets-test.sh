#!/usr/bin/env bash
# Behavioural tests for the combined SOPS secrets file, with a fake sops.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
check() { local desc=$1; shift; if "$@"; then ok "$desc"; else no "$desc"; fi; }
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

home=$tmp/home
mkdir -p "$home/.config/sops" "$tmp/bin"
: >"$home/.config/sops/keys.age"
printf 'encrypted\n' >"$tmp/secrets.yaml"

cat >"$tmp/bin/sops" <<'EOF'
#!/bin/sh
printf 'sops\n' >>"$SECRETS_LOG"
printf 'NEURALWATT_API_KEY=%s\n' "$FAKE_NEURALWATT"
printf 'TINYFISH_API_KEY=%s\n' "$FAKE_TINYFISH"
[ -n "$FAKE_PAT" ] && printf 'GITHUB_PERSONAL_PAT=%s\n' "$FAKE_PAT"
[ -n "$FAKE_WORK_PAT" ] && printf 'GITHUB_WORK_PAT=%s\n' "$FAKE_WORK_PAT"
exit 0
EOF
# The token is exported by zsh, never handed to gh: any gh call is a failure.
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
printf 'gh %s\n' "$*" >>"$SECRETS_LOG"
EOF
chmod +x "$tmp/bin/sops" "$tmp/bin/gh"

run() {
    env -i HOME="$home" PATH="$tmp/bin:/usr/bin:/bin" \
        SECRETS_LOG="$tmp/log" MISE_ENV="${MISE_ENV-}" \
        FAKE_NEURALWATT="${FAKE_NEURALWATT-nw-test}" \
        FAKE_TINYFISH="${FAKE_TINYFISH-tf-test}" \
        FAKE_PAT="${FAKE_PAT-ghp_test}" \
        FAKE_WORK_PAT="${FAKE_WORK_PAT-ghp_work}" \
        DOTFILES_SECRETS="$tmp/secrets.yaml" \
        sh "$root/scripts/secrets.sh" >"$tmp/out" 2>&1
}
decrypts() { grep -c '^sops$' "$tmp/log"; }

secrets=$home/.config/secrets.env
token=$home/.config/github-token

check "decrypt exits 0" run
check "the provider keys are written" \
    grep -qx 'NEURALWATT_API_KEY=nw-test' "$secrets"
check "secrets.env is mode 600" test "$(mode_of "$secrets")" = 600
check "a personal machine gets the personal PAT" test "$(cat "$token" 2>/dev/null)" = ghp_test
check "the token file is mode 600" test "$(mode_of "$token" 2>/dev/null)" = 600
check "the PATs stay out of the Maki cache" bash -c "! grep -q ghp_ '$secrets'"
check "the PATs are never printed" bash -c "! grep -q ghp_ '$tmp/out'"
check "gh is never called" bash -c "! grep -q '^gh ' '$tmp/log'"

run
check "an unchanged file skips the second decrypt" test "$(decrypts)" -eq 1

chmod 644 "$token"
run
check "a loosened token file is tightened without decrypting" \
    test "$(mode_of "$token")" = 600 -a "$(decrypts)" -eq 1

rm "$token"
run
check "a deleted token file is restored without a changed file" \
    test "$(cat "$token" 2>/dev/null)" = ghp_test -a "$(decrypts)" -eq 2

MISE_ENV=desktop,work run
check "a work machine gets only the work PAT, even with an unchanged file" \
    test "$(cat "$token" 2>/dev/null)" = ghp_work -a "$(decrypts)" -eq 3
MISE_ENV=desktop,work run
check "a work machine skips the second decrypt" test "$(decrypts)" -eq 3

printf 'changed\n' >"$tmp/secrets.yaml"
run
check "a changed file decrypts again" test "$(decrypts)" -eq 4

printf 'old\n' >"$secrets"
printf 'changed2\n' >"$tmp/secrets.yaml"
if FAKE_NEURALWATT='' run; then no "missing provider keys fail"; else ok "missing provider keys fail"; fi
check "missing provider keys keep the existing file" grep -qx old "$secrets"

printf 'changed3\n' >"$tmp/secrets.yaml"
FAKE_PAT='' run
check "an empty PAT removes the token file" test ! -e "$token"
check "an empty PAT warns that git and gh have no token" grep -q 'no GITHUB_PERSONAL_PAT' "$tmp/out"
run_before=$(decrypts)
FAKE_PAT='' run
check "an empty PAT is not decrypted again on every run" test "$(decrypts)" -eq "$run_before"
MISE_ENV=work FAKE_PAT='' run
check "switching to work picks up the work PAT despite the empty personal one" \
    test "$(cat "$token" 2>/dev/null)" = ghp_work

rm "$home/.config/sops/keys.age"
printf 'changed4\n' >"$tmp/secrets.yaml"
run_before=$(decrypts)
run
check "a machine without the age identity is left alone" test "$(decrypts)" -eq "$run_before"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
