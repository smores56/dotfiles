#!/usr/bin/env bash
# Behavioural tests for ~/.local/bin/sops-age-key, the identity sops reads
# through SOPS_AGE_KEY_CMD: the YubiKey handle wins when it is provisioned, the
# passphrase-wrapped admin identity is the fallback, and a retired plaintext
# identity stops the command.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
script=$root/home/.local/bin/sops-age-key
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }

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

# 1. The YubiKey identity wins, and nothing is decrypted with a passphrase.
printf '# public key: age1test\nAGE-PLUGIN-FIDO2-HMAC-1TEST\n' >"$fido2"
chmod 600 "$fido2"
: >"$tmp/log"
if got=$(run); then
    ok "a provisioned YubiKey identity is exported"
else
    no "a provisioned YubiKey identity is exported"
    sed 's/^/     /' "$tmp/err" >&2
fi
[ "$got" = '# public key: age1test
AGE-PLUGIN-FIDO2-HMAC-1TEST' ] && ok "the plugin handle reaches sops verbatim" \
    || no "the plugin handle reaches sops verbatim (got '$got')"
[ ! -s "$tmp/log" ] && ok "the admin key is not decrypted when the token is enrolled" \
    || no "the admin key is not decrypted when the token is enrolled"

# 2. Without it, the passphrase-wrapped admin identity is unwrapped by age.
rm "$fido2"
: >"$admin"
: >"$tmp/log"
if got=$(run); then
    ok "the admin identity is decrypted on request"
else
    no "the admin identity is decrypted on request"
fi
[ "$got" = 'FAKE-ADMIN-IDENTITY' ] && ok "age's identity is what sops reads" \
    || no "age's identity is what sops reads (got '$got')"
grep -qx "age --decrypt $admin" "$tmp/log" \
    && ok "age decrypts the wrapped admin identity" \
    || no "age decrypts the wrapped admin identity ($(cat "$tmp/log"))"

# 3. Neither identity: fail, naming both files.
rm "$admin"
if run >/dev/null; then
    no "a machine with no identity fails"
else
    ok "a machine with no identity fails"
fi
out=$(cat "$tmp/err")
case $out in
    *"$admin is missing or unreadable"*) ok "the failure names the admin identity" ;;
    *) no "the failure names the admin identity (got '$out')" ;;
esac
case $out in
    *"$fido2"*) ok "the failure names the YubiKey identity" ;;
    *) no "the failure names the YubiKey identity (got '$out')" ;;
esac

# 4. A retired plaintext identity stops the command before anything decrypts.
mkdir -p "$config/sops/age"
: >"$config/sops/age/keys.txt"
printf 'AGE-PLUGIN-FIDO2-HMAC-1TEST\n' >"$fido2"
if run >/dev/null; then
    no "a retired plaintext identity fails"
else
    ok "a retired plaintext identity fails"
fi
out=$(cat "$tmp/err")
case $out in
    *'remove the retired plaintext identity'*) ok "the failure names the retired file" ;;
    *) no "the failure names the retired file (got '$out')" ;;
esac

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
