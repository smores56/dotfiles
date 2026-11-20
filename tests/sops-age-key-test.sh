#!/usr/bin/env bash
# ~/.local/bin/sops-age-key, the identity sops reads through SOPS_AGE_KEY_CMD.
# sops runs the command once per recipient stanza and passes the stanza's
# recipient in SOPS_AGE_RECIPIENT, so the command answers for that one
# recipient: the matching YubiKey handle, the passphrase-wrapped admin identity
# for the admin recipient, or nothing for a recipient this machine cannot read.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

script=$root/home/.local/bin/sops-age-key
home=$tmp/home
config=$home/.config
mkdir -p "$config/sops" "$tmp/bin" "$tmp/bin-noage"

cat >"$tmp/bin/age" <<'EOF'
#!/bin/sh
printf 'age %s\n' "$*" >>"$AGE_LOG"
printf 'FAKE-ADMIN-IDENTITY\n'
EOF
# The production probe lists the FIDO devices it can open; the stub reports one
# only when the case asks for a token.
cat >"$tmp/bin/systemd-cryptenroll" <<'EOF'
#!/bin/sh
[ -n "${FAKE_FIDO-}" ] && echo /dev/hidraw1
exit 0
EOF
cat >"$tmp/bin/age-plugin-fido2-hmac" <<'EOF'
#!/bin/sh
exit 0
EOF
cp "$tmp/bin/systemd-cryptenroll" "$tmp/bin-noage/systemd-cryptenroll"
chmod +x "$tmp/bin/age" "$tmp/bin/systemd-cryptenroll" \
    "$tmp/bin/age-plugin-fido2-hmac" "$tmp/bin-noage/systemd-cryptenroll"

fido2=$config/sops/fido2-identity.txt
admin=$config/sops/keys.age

valid_admin() { printf 'age-encryption.org/v1\nfake\n' >"$admin"; }

# Two enrolled keys and the admin recipient the passphrase identity owns.
write_handles() {
    cat >"$fido2" <<'EOF'
# created: test
# public key: age1one
# public key (pq safe): age1pqone
AGE-PLUGIN-FIDO2-HMAC-1ONE
# public key: age1two
AGE-PLUGIN-FIDO2-HMAC-1TWO
EOF
    chmod 600 "$fido2"
}
write_handles

run() {
    env -i HOME="$home" XDG_CONFIG_HOME="$config" \
        PATH="${RUN_PATH:-$tmp/bin:/usr/bin:/bin}" \
        AGE_LOG="$tmp/log" \
        SOPS_AGE_RECIPIENT="${RECIP-}" \
        SOPS_AGE_FIDO2_PRESENT="${PRESENT-}" \
        FAKE_FIDO="${FIDO-}" \
        SOPS_AGE_KEY="${SKEY-}" \
        SOPS_AGE_KEY_FILE="${SKEYFILE-}" \
        SOPS_AGE_SSH_PRIVATE_KEY_FILE="${SSHKEY-}" \
        SOPS_AGE_BIN="${SBIN-}" \
        bash "$script" "$@" 2>"$tmp/err"
}

reset_log() { : >"$tmp/log"; }
age_calls() { [ -s "$tmp/log" ] && wc -l <"$tmp/log" | tr -d ' ' || echo 0; }

# 1. The stanza's recipient selects exactly one handle; no passphrase is read.
reset_log
RECIP=age1two FIDO=1 assert "the matching recipient selects its identity" run
expect "only the matching handle is printed" 'AGE-PLUGIN-FIDO2-HMAC-1TWO' "$out"
expect "the admin identity is not decrypted" 0 "$(age_calls)"

# 2. A recipient this machine cannot serve prints nothing and still succeeds,
#    so sops can try the next stanza.
reset_log
RECIP=age1someoneelse FIDO=1 assert "an unowned recipient is skipped" run
expect "an unowned recipient prints no identity" '' "$out"
expect "an unowned recipient does not decrypt the admin key" 0 "$(age_calls)"

# 3. The admin recipient with no usable token prompts through age, once.
reset_log
valid_admin
RECIP=age1admin PRESENT=0 assert "the admin recipient decrypts the wrapped identity" run
expect "age's identity is what sops reads" FAKE-ADMIN-IDENTITY "$out"
expect "age decrypts the wrapped admin identity" "age --decrypt $admin" "$(cat "$tmp/log")"

# 4. The admin recipient with a usable token prints nothing: the token path is
#    preferred, and the passphrase is not read.
reset_log
RECIP=age1admin FIDO=1 assert "the admin recipient defers to a usable token" run
expect "the admin stanza emits nothing when a token is usable" '' "$out"
expect "the admin identity is not decrypted when a token is usable" 0 "$(age_calls)"

# 4b. An attached token this machine has no handle for cannot answer any stanza,
#     so the admin recipient still falls back to the passphrase.
reset_log
mv "$fido2" "$fido2.away"
valid_admin
RECIP=age1admin FIDO=1 assert "a token without handles falls back to the passphrase" run
expect "the admin identity answers when no handle exists" FAKE-ADMIN-IDENTITY "$out"
mv "$fido2.away" "$fido2"

# 5. A handle whose token is absent fails loudly instead of silently emitting
#    an identity the plugin cannot use.
reset_log
RECIP=age1one PRESENT=0 assert_not "a matched handle with no token fails" run
contains "the failure names the recipient" 'age1one' "$(cat "$tmp/err")"
expect "a matched handle with no token does not read the passphrase" 0 "$(age_calls)"

# 6. Without a recipient (older sops or a manual run), a usable token exports
#    every handle, and no comments leak into sops's parser.
reset_log
FIDO=1 assert "without a recipient the handles are exported" run
expect "every handle is printed, comments excluded" 'AGE-PLUGIN-FIDO2-HMAC-1ONE
AGE-PLUGIN-FIDO2-HMAC-1TWO' "$out"
expect "the passphrase is not read when handles are available" 0 "$(age_calls)"

# 7. Without a recipient and without a token, the passphrase is the fallback.
reset_log
valid_admin
PRESENT=0 assert "without a recipient or token the admin identity is used" run
expect "the admin identity is the fallback" FAKE-ADMIN-IDENTITY "$out"

# 8. Neither identity: fail and name both files.
reset_log
rm "$fido2" "$admin"
assert_not "a machine with no identity fails" run
contains "the failure names the admin identity" "$admin is missing, empty" "$(cat "$tmp/err")"
contains "the failure names the handle file" "$fido2" "$(cat "$tmp/err")"

# 9. --check answers "can this machine produce an identity" without calling age,
#    and the answer matches the routing path.
write_handles
valid_admin
reset_log
PRESENT=0 assert "--check accepts a readable admin identity" run --check
expect "--check prints nothing" '' "$out"
expect "--check does not read the passphrase" 0 "$(age_calls)"
rm "$admin"
FIDO=1 assert "--check accepts a usable token without the admin key" run --check
expect "the token path needs no passphrase" '' "$out"
valid_admin
: >"$admin"
PRESENT=0 assert_not "--check rejects an empty admin identity" run --check
printf 'not-an-age-file\n' >"$admin"
PRESENT=0 assert_not "--check rejects a non-age admin file" run --check
valid_admin
PRESENT=0 RUN_PATH="$tmp/bin-noage:/usr/bin:/bin" assert_not "--check rejects a missing age helper" run --check
rm "$admin"
PRESENT=0 assert_not "--check rejects a machine with no identity" run --check
expect "--check is silent on stdout when it rejects" '' "$out"
contains "--check explains the rejection on stderr" 'no usable SOPS identity' "$(cat "$tmp/err")"

# 10. The retired plaintext identity still stops a user, including --check.
valid_admin
mkdir -p "$config/sops/age"
printf 'legacy\n' >"$config/sops/age/keys.txt"
assert_not "a retired plaintext identity fails" run
contains "the failure names the retired file" 'remove the retired plaintext identity' "$(cat "$tmp/err")"
assert_not "--check refuses a retired plaintext identity" run --check
rm -rf "$config/sops/age"

# 11. An identity source outside this wrapper is refused rather than silently
#     overriding the guard.
valid_admin
SKEYFILE=$tmp/elsewhere assert_not "SOPS_AGE_KEY_FILE is refused" run
contains "the failure names the variable" 'SOPS_AGE_KEY_FILE' "$(cat "$tmp/err")"
SKEY=$tmp/not-an-identity assert_not "SOPS_AGE_KEY is refused" run
SSHKEY=$tmp/ssh-key assert_not "SOPS_AGE_SSH_PRIVATE_KEY_FILE is refused" run
contains "the SSH failure names the variable" 'SOPS_AGE_SSH_PRIVATE_KEY' "$(cat "$tmp/err")"

# 12. The probe uses systemd-cryptenroll's usable-device list.
write_handles
reset_log
RECIP=age1one FIDO=1 assert "a listed FIDO device counts as usable" run
expect "the handle is selected through the real probe" 'AGE-PLUGIN-FIDO2-HMAC-1ONE' "$out"
RECIP=age1one FIDO='' assert_not "no listed FIDO device is not usable" run
contains "the no-device failure names the recipient" 'age1one' "$(cat "$tmp/err")"

# 13. The explicit override beats the probe in both directions.
RECIP=age1one PRESENT=1 FIDO='' assert "the presence override can force a token" run
expect "the forced token selects the handle" 'AGE-PLUGIN-FIDO2-HMAC-1ONE' "$out"
RECIP=age1one PRESENT=0 FIDO=1 assert_not "the presence override can force the passphrase path" run

# 14. A malformed or duplicated block for the selected recipient is a hard
#     failure, not a silent skip; an unowned handle is named.
cat >"$fido2" <<'EOF'
# public key: age1bad
AGE-PLUGIN-FIDO2-HMAC-1BAD!
# admin: age1admin
EOF
RECIP=age1bad FIDO=1 assert_not "a malformed identity line fails" run
contains "the malformed-line failure names the file" "$fido2" "$(cat "$tmp/err")"

cat >"$fido2" <<'EOF'
# public key: age1dup
AGE-PLUGIN-FIDO2-HMAC-1DUP
# public key: age1dup
AGE-PLUGIN-FIDO2-HMAC-1DUP
# admin: age1admin
EOF
RECIP=age1dup FIDO=1 assert_not "a duplicated recipient fails" run
contains "the duplicate failure names the recipient" 'age1dup' "$(cat "$tmp/err")"

cat >"$fido2" <<'EOF'
AGE-PLUGIN-FIDO2-HMAC-1ORPHAN
# public key: age1one
AGE-PLUGIN-FIDO2-HMAC-1ONE
# admin: age1admin
EOF
RECIP=age1one FIDO=1 assert_not "an unowned handle fails" run
contains "the unowned-handle failure names the file" "$fido2" "$(cat "$tmp/err")"

# 15. A pinned age path is both testable and outside a project's PATH.
write_handles
valid_admin
SBIN=$tmp/bin/age PRESENT=0 assert "--check accepts a pinned age" run --check
SBIN=$tmp/no-such-age PRESENT=0 assert_not "--check rejects a missing pinned age" run --check

finish
