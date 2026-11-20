#!/usr/bin/env bash
# The routing in sops-age-key depends on sops passing the stanza's recipient in
# SOPS_AGE_RECIPIENT. Pin that contract against a real sops and age; skip where
# either is missing.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

if ! command -v sops >/dev/null 2>&1 || ! command -v age-keygen >/dev/null 2>&1; then
    skip_all "sops or age-keygen not installed"
fi

work=$tmp/sops
mkdir -p "$work"
age-keygen -o "$work/id.txt" 2>/dev/null || skip_all "age-keygen failed"
recip=$(age-keygen -y "$work/id.txt" 2>/dev/null) || skip_all "age-keygen -y failed"

cat >"$work/.sops.yaml" <<EOF
creation_rules:
  - path_regex: .*
    key_groups:
      - age:
          - $recip
EOF
printf 'secret: value\n' >"$work/plain.yaml"
if ! (cd "$work" && sops --encrypt --input-type yaml --output-type yaml plain.yaml >enc.yaml 2>enc.err); then
    skip_all "sops encrypt failed: $(tr '\n' ' ' <"$work/enc.err")"
fi

cat >"$work/keycmd" <<EOF
#!/bin/sh
printf '%s\n' "\$SOPS_AGE_RECIPIENT" >> "$work/log"
cat "$work/id.txt"
EOF
chmod +x "$work/keycmd"

: >"$work/log"
if ! got=$(cd "$work" && SOPS_AGE_KEY_CMD="$work/keycmd" sops --decrypt \
        --input-type yaml --output-type yaml enc.yaml 2>"$work/err"); then
    no "sops decrypts through SOPS_AGE_KEY_CMD"
    indent <"$work/err"
    finish
    exit 1
fi
ok "sops decrypts through SOPS_AGE_KEY_CMD"
contains "the plaintext survives the round trip" 'secret: value' "$got"
contains "sops passes the stanza recipient to the command" "$recip" "$(cat "$work/log")"
expect "the command runs once for a one-recipient file" 1 "$(grep -c . "$work/log")"

finish
