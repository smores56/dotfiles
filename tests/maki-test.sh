#!/usr/bin/env bash
# The ~/.local/bin/maki key wrapper: a stand-in binary reports the provider keys
# it received.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

wrapper=$root/home/.local/bin/maki
h=$tmp/home
secrets=$h/.config/maki/secrets.env
mkdir -p "$h/.local/libexec" "$h/.config/maki"
cat >"$h/.local/libexec/maki" <<'EOF'
#!/bin/sh
printf 'child:%s:%s:%s\n' "${NEURALWATT_API_KEY:-unset}" "${TINYFISH_API_KEY:-unset}" "$*"
EOF
chmod +x "$h/.local/libexec/maki"
run() { env -i HOME="$h" PATH=/usr/bin:/bin sh "$wrapper" "$@"; }
stderr_of() { { run >/dev/null; } 2>&1; }

# Every shape the old zsh launcher accepted: comments, blank lines, CRLF, spaces
# around =, an export prefix, and one layer of quotes.
printf '# provider keys\r\n\r\n  # indented comment\r\nexport NEURALWATT_API_KEY = "nw-test"  \r\n\r\nTINYFISH_API_KEY=tf-test\r\n' >"$secrets"
chmod 600 "$secrets"

expect "maki receives the provider keys and its arguments" "child:nw-test:tf-test:--session x" \
    "$(run --session x 2>/dev/null)"
expect "maki parses the file without complaints" "" "$(stderr_of)"
expect "the keys never reach the caller" "unset:unset" \
    "$(env -i HOME="$h" PATH=/usr/bin:/bin sh -c '"$1" >/dev/null 2>&1; printf %s "${NEURALWATT_API_KEY:-unset}:${TINYFISH_API_KEY:-unset}"' sh "$wrapper")"

printf "NEURALWATT_API_KEY='single'\nOTHER=x\nno-equals-here\n" >"$secrets"
expect "single quotes are cosmetic too" "child:single:unset:" "$(run 2>/dev/null)"
expect "unknown names and lines without = are reported, without values" \
    "maki: $secrets:2: skipped (OTHER is not a Maki provider key)|maki: $secrets:3: skipped (no =)" \
    "$(stderr_of | paste -sd'|' -)"

chmod 644 "$secrets"
contains "a readable secrets file is flagged" 'is mode 644, expected 600' "$(stderr_of)"

rm "$secrets"
expect "a missing secrets file still starts maki" "child:unset:unset:" "$(run 2>/dev/null)"
contains "a missing secrets file is reported" 'secrets.env is missing' "$(stderr_of)"

rm "$h/.local/libexec/maki"
run >/dev/null 2>"$tmp/err"
expect "a missing binary fails with 127" 127 $?
contains "the failure names the installer" install-maki.sh "$(cat "$tmp/err")"

if [ "$(uname -s)-$(uname -m)" = Linux-x86_64 ]; then
    expect "the installer puts the binary off PATH" "would install $tmp/p/libexec/maki" \
        "$(bash "$root/scripts/install-maki.sh" --dry-run --prefix "$tmp/p" | grep '^would install')"
fi

finish
