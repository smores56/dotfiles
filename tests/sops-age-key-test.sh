#!/usr/bin/env bash
# ~/.local/bin/sops-age-key, the identity sops reads through SOPS_AGE_KEY_CMD:
# the YubiKey handle wins when provisioned, the passphrase-wrapped admin
# identity is the fallback, and a retired plaintext identity stops the command.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

script=$root/home/.local/bin/sops-age-key
home=$tmp/home
config=$home/.config
mkdir -p "$config/sops" "$tmp/bin"

cat >"$tmp/bin/age" <<'EOF'
#!/bin/sh
printf 'age %s\n' "$*" >>"$AGE_LOG"
printf 'FAKE-ADMIN-IDENTITY\n'
EOF
chmod +x "$tmp/bin/age"

run() {
    env -i HOME="$home" XDG_CONFIG_HOME="$config" PATH="$tmp/bin:/usr/bin:/bin" \
        AGE_LOG="$tmp/log" bash "$script" 2>"$tmp/err"
}

fido2=$config/sops/fido2-identity.txt
admin=$config/sops/keys.age

printf '# public key: age1test\nAGE-PLUGIN-FIDO2-HMAC-1TEST\n' >"$fido2"
chmod 600 "$fido2"
: >"$tmp/log"
assert "a provisioned YubiKey identity is exported" run
expect "the plugin handle reaches sops verbatim" '# public key: age1test
AGE-PLUGIN-FIDO2-HMAC-1TEST' "$out"
assert_not "the admin key is not decrypted when the token is enrolled" test -s "$tmp/log"

rm "$fido2"
: >"$admin"
: >"$tmp/log"
assert "the admin identity is decrypted on request" run
expect "age's identity is what sops reads" FAKE-ADMIN-IDENTITY "$out"
expect "age decrypts the wrapped admin identity" "age --decrypt $admin" "$(cat "$tmp/log")"

rm "$admin"
assert_not "a machine with no identity fails" run
contains "the failure names the admin identity" "$admin is missing or unreadable" "$(cat "$tmp/err")"
contains "the failure names the YubiKey identity" "$fido2" "$(cat "$tmp/err")"

mkdir -p "$config/sops/age"
: >"$config/sops/age/keys.txt"
printf 'AGE-PLUGIN-FIDO2-HMAC-1TEST\n' >"$fido2"
assert_not "a retired plaintext identity fails" run
contains "the failure names the retired file" 'remove the retired plaintext identity' "$(cat "$tmp/err")"

finish
