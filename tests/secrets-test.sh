#!/usr/bin/env bash
# scripts/secrets.sh against a fake sops.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

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
[ -n "$FAKE_ACCESS_ID" ] && printf 'CLOUDFLARE_ACCESS_CLIENT_ID=%s\n' "$FAKE_ACCESS_ID"
[ -n "$FAKE_ACCESS_SECRET" ] && printf 'CLOUDFLARE_ACCESS_CLIENT_SECRET=%s\n' "$FAKE_ACCESS_SECRET"
exit 0
EOF
# The token is exported by the shell env, never handed to gh: any gh call is a failure.
cat >"$tmp/bin/gh" <<'EOF'
#!/bin/sh
printf 'gh %s\n' "$*" >>"$SECRETS_LOG"
EOF
# Stands in for `mise exec`, which exports the saved set only when it is non-empty.
cat >"$tmp/bin/mise" <<'EOF'
#!/bin/sh
printf 'mise %s\n' "$*" >>"$SECRETS_LOG"
[ -z "${FAKE_MISE_FAIL-}" ] || exit 1
[ "$1 $2" = "exec --" ] || exit 2
shift 2
[ -z "${FAKE_MISE_ENV-}" ] || { MISE_ENV=$FAKE_MISE_ENV; export MISE_ENV; }
exec "$@"
EOF
chmod +x "$tmp/bin/sops" "$tmp/bin/gh" "$tmp/bin/mise"

# BY_HAND=1 leaves MISE_ENV unset, as a shell outside mise does.
run() {
    local mise_env=(MISE_ENV="${MISE_ENV-}")
    [ -z "${BY_HAND-}" ] || mise_env=()
    env -i HOME="$home" PATH="$tmp/bin:/usr/bin:/bin" \
        SECRETS_LOG="$tmp/log" ${mise_env[@]+"${mise_env[@]}"} \
        FAKE_MISE_ENV="${FAKE_MISE_ENV-}" FAKE_MISE_FAIL="${FAKE_MISE_FAIL-}" \
        FAKE_NEURALWATT="${FAKE_NEURALWATT-nw-test}" \
        FAKE_TINYFISH="${FAKE_TINYFISH-tf-test}" \
        FAKE_PAT="${FAKE_PAT-ghp_test}" \
        FAKE_WORK_PAT="${FAKE_WORK_PAT-ghp_work}" \
        FAKE_ACCESS_ID="${FAKE_ACCESS_ID-cf-id-test}" \
        FAKE_ACCESS_SECRET="${FAKE_ACCESS_SECRET-cf-secret-test}" \
        DOTFILES_SECRETS="$tmp/secrets.yaml" \
        sh "$root/scripts/secrets.sh" "$@" >"$tmp/out" 2>&1
}
decrypts() { grep -c '^sops$' "$tmp/log"; }

secrets=$home/.config/maki/secrets.env
token=$home/.config/gh/token
access=$home/.config/cloudflare/access.env
state=$home/.local/state/dotfiles/secrets.sha256

assert "decrypt exits 0" run
assert "the provider keys are written" \
    grep -qx 'NEURALWATT_API_KEY=nw-test' "$secrets"
assert "secrets.env is mode 600" test "$(mode_of "$secrets")" = 600
assert "a personal machine gets the personal PAT" test "$(cat "$token" 2>/dev/null)" = ghp_test
assert "the token file is mode 600" test "$(mode_of "$token" 2>/dev/null)" = 600
assert_not "the PATs stay out of the Maki cache" grep -q ghp_ "$secrets"
assert_not "the PATs are never printed" grep -q ghp_ "$tmp/out"
assert_not "gh is never called" grep -q '^gh ' "$tmp/log"
assert "the Access client id is written where the wrapper reads it" \
    grep -qx 'CLOUDFLARE_ACCESS_CLIENT_ID=cf-id-test' "$access"
assert "the Access secret is written where the wrapper reads it" \
    grep -qx 'CLOUDFLARE_ACCESS_CLIENT_SECRET=cf-secret-test' "$access"
assert "the Access token file is mode 600" test "$(mode_of "$access")" = 600
assert "the Access token directory is private" test "$(mode_of "$home/.config/cloudflare")" = 700
assert_not "the Access token stays out of the Maki cache" grep -q cf-secret-test "$secrets"
assert_not "the Access token is never printed" grep -q cf-secret-test "$tmp/out"

run
assert "an unchanged file skips the second decrypt" test "$(decrypts)" -eq 1

chmod 644 "$token"
run
assert "a loosened token file is tightened without decrypting" \
    test "$(mode_of "$token")" = 600 -a "$(decrypts)" -eq 1

rm "$token"
run
assert "a deleted token file is restored without a changed file" \
    test "$(cat "$token" 2>/dev/null)" = ghp_test -a "$(decrypts)" -eq 2

MISE_ENV=desktop,work run
assert "a work machine gets only the work PAT, even with an unchanged file" \
    test "$(cat "$token" 2>/dev/null)" = ghp_work -a "$(decrypts)" -eq 3
MISE_ENV=desktop,work run
assert "a work machine skips the second decrypt" test "$(decrypts)" -eq 3

printf 'changed\n' >"$tmp/secrets.yaml"
run
assert "a changed file decrypts again" test "$(decrypts)" -eq 4

printf 'old\n' >"$secrets"
printf 'changed2\n' >"$tmp/secrets.yaml"
FAKE_NEURALWATT='' assert_not "missing provider keys fail" run
assert "missing provider keys keep the existing file" grep -qx old "$secrets"

printf 'changed3\n' >"$tmp/secrets.yaml"
FAKE_PAT='' run
assert "an empty PAT leaves the token file alone" test -e "$token"
assert "an empty PAT warns that git and gh have no token" grep -q 'no GITHUB_PERSONAL_PAT' "$tmp/out"
run_before=$(decrypts)
FAKE_PAT='' run
assert "an empty PAT is not decrypted again on every run" test "$(decrypts)" -eq "$run_before"
MISE_ENV=work FAKE_PAT='' run
assert "switching to work picks up the work PAT despite the empty personal one" \
    test "$(cat "$token" 2>/dev/null)" = ghp_work

# --- the Access service token
# The case above left the work PAT marker in the state; a fixed environment
# keeps this block on the Access marker alone.
MISE_ENV=work

before=$(decrypts)
run
assert "an untouched machine does not decrypt for the Access token again" \
    test "$(decrypts)" -eq "$before"

chmod 644 "$access"
run
assert "a loosened Access token file is tightened without decrypting" \
    test "$(mode_of "$access")" = 600 -a "$(decrypts)" -eq "$before"

rm "$access"
run
assert "a deleted Access token file is restored without a changed file" \
    test "$(mode_of "$access")" = 600 -a "$(decrypts)" -eq "$((before + 1))"

# A state file from before the token existed carries two fields.
sha=$(cut -d' ' -f1 "$state")
printf '%s GITHUB_PERSONAL_PAT\n' "$sha" >"$state"
before=$(decrypts)
run
assert "a state file without an Access marker decrypts once more" \
    test "$(decrypts)" -eq "$((before + 1))"

printf 'access1\n' >"$tmp/secrets.yaml"
before=$(decrypts)
FAKE_ACCESS_ID='' run
assert "a cipher without the Access pair leaves the token file alone" test -e "$access"
assert "a cipher without the Access pair warns" grep -q 'no CLOUDFLARE_ACCESS_CLIENT_ID' "$tmp/out"
assert "a cipher without the Access pair decrypts once, then settles" \
    test "$(decrypts)" -eq "$((before + 1))"
before=$(decrypts)
FAKE_ACCESS_ID='' run
assert "the absent Access pair is not decrypted again on every run" \
    test "$(decrypts)" -eq "$before"
printf 'access2\n' >"$tmp/secrets.yaml"
before=$(decrypts)
run
assert "the Access token comes back with the cipher's pair" \
    test "$(decrypts)" -eq "$((before + 1))"
assert "the restored Access token file is mode 600" \
    test "$(mode_of "$access")" = 600
MISE_ENV=

rm "$home/.config/sops/keys.age"
printf 'changed4\n' >"$tmp/secrets.yaml"
run_before=$(decrypts)
run
assert "a machine without the age identity is left alone" test "$(decrypts)" -eq "$run_before"

# An absent key must not delete a credential, because a stale checkout carries an
# older cipher than the one that delivered it. Removal is opt-in.
: >"$home/.config/sops/keys.age"
printf 'prune1\n' >"$tmp/secrets.yaml"
run
assert "--prune guard setup: token exists" test -e "$token"
assert "--prune guard setup: the Access file exists" test -e "$access"
printf 'prune2\n' >"$tmp/secrets.yaml"
FAKE_PAT='' FAKE_ACCESS_ID='' FAKE_ACCESS_SECRET='' run
assert "an absent PAT leaves the token in place" test -e "$token"
assert "an absent Access pair leaves access.env in place" test -e "$access"
assert "an absent pair says how to remove it" grep -q -- '--prune removes it' "$tmp/out"
FAKE_PAT='' FAKE_ACCESS_ID='' FAKE_ACCESS_SECRET='' run --prune
assert "--prune removes the token" test ! -e "$token"
assert "--prune removes access.env" test ! -e "$access"

# A hand run outside mise has no MISE_ENV; the set must come from mise, or a
# work machine silently gets the personal PAT.
printf 'hand1\n' >"$tmp/secrets.yaml"
BY_HAND=1 FAKE_MISE_ENV=desktop,work run
assert "a hand run on a work machine gets the work PAT" \
    test "$(cat "$token" 2>/dev/null)" = ghp_work
assert "a hand run asks mise for the environment set" grep -q '^mise exec' "$tmp/log"
printf 'hand2\n' >"$tmp/secrets.yaml"
BY_HAND=1 run
assert "a hand run where mise has no set gets the personal PAT" \
    test "$(cat "$token" 2>/dev/null)" = ghp_test
printf 'hand3\n' >"$tmp/secrets.yaml"
BY_HAND=1 FAKE_MISE_FAIL=1 assert_not "a hand run fails when mise cannot report the set" run
assert "a failed mise lookup leaves the token alone" test "$(cat "$token" 2>/dev/null)" = ghp_test
assert "a failed mise lookup says how to run it" grep -q 'mise exec -- sh scripts/secrets.sh' "$tmp/out"

finish
