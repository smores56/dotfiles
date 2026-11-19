#!/usr/bin/env bash
# Behavioral tests for the ~/.local/bin/maki key wrapper: a stand-in binary
# reports the provider keys it received. Hermetic; no network.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
wrapper=$root/home/.local/bin/maki

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
expect() {  # expect <desc> <want> <got>
    if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$2', got '$3')"; fi
}

h=$tmp/home
mkdir -p "$h/.local/libexec" "$h/.config"
cat >"$h/.local/libexec/maki" <<'EOF'
#!/bin/sh
printf 'child:%s:%s:%s\n' "${NEURALWATT_API_KEY:-unset}" "${TINYFISH_API_KEY:-unset}" "$*"
EOF
chmod +x "$h/.local/libexec/maki"
run() { env -i HOME="$h" PATH=/usr/bin:/bin sh "$wrapper" "$@"; }

# Every shape the zsh launcher accepted: comments, blank lines, CRLF, spaces
# around =, an export prefix, and one layer of quotes.
printf '# provider keys\r\n\r\n  # indented comment\r\nexport NEURALWATT_API_KEY = "nw-test"  \r\n\r\nTINYFISH_API_KEY=tf-test\r\n' \
    >"$h/.config/secrets.env"
chmod 600 "$h/.config/secrets.env"

expect "maki receives the provider keys and its arguments" "child:nw-test:tf-test:--session x" \
    "$(run --session x 2>/dev/null)"
expect "maki parses the file without complaints" "" "$(run 2>&1 >/dev/null)"
expect "the keys never reach the caller" "unset:unset" \
    "$(env -i HOME="$h" PATH=/usr/bin:/bin sh -c '"$1" >/dev/null 2>&1; printf %s "${NEURALWATT_API_KEY:-unset}:${TINYFISH_API_KEY:-unset}"' sh "$wrapper")"

printf "NEURALWATT_API_KEY='single'\nOTHER=x\nno-equals-here\n" >"$h/.config/secrets.env"
expect "single quotes are cosmetic too" "child:single:unset:" "$(run 2>/dev/null)"
expect "unknown names and lines without = are reported, without values" \
    "maki: $h/.config/secrets.env:2: skipped (OTHER is not a Maki provider key)|maki: $h/.config/secrets.env:3: skipped (no =)" \
    "$(run 2>&1 >/dev/null | paste -sd'|' -)"

chmod 644 "$h/.config/secrets.env"
err=$(run 2>&1 >/dev/null)
expect "a readable secrets file is flagged" yes \
    "$([[ $err == *'is mode 644, expected 600'* ]] && echo yes || echo no)"

rm "$h/.config/secrets.env"
expect "a missing secrets file still starts maki" "child:unset:unset:" "$(run 2>/dev/null)"
err=$(run 2>&1 >/dev/null)
expect "a missing secrets file is reported" yes \
    "$([[ $err == *'secrets.env is missing'* ]] && echo yes || echo no)"

rm "$h/.local/libexec/maki"
run >/dev/null 2>"$tmp/err"
expect "a missing binary fails with 127" 127 $?
expect "the failure names the installer" yes \
    "$(grep -q 'install-maki.sh' "$tmp/err" && echo yes || echo no)"

if [ "$(uname -s)-$(uname -m)" = Linux-x86_64 ]; then
    expect "the installer puts the binary off PATH" "would install $tmp/p/.local/libexec/maki" \
        "$(bash "$root/scripts/install-maki.sh" --dry-run --prefix "$tmp/p" | grep '^would install')"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
