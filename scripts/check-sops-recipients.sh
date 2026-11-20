#!/usr/bin/env bash
# Every tracked ciphertext in each given checkout must be wrapped to exactly the
# canonical readers. The config is $SOPS_CONFIG, or the dotfiles' copy.
set -euo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
config=${SOPS_CONFIG:-$here/../home/.config/sops/sops.yaml}
if [ ! -r "$config" ]; then
    printf 'check-sops-recipients: no SOPS config at %s\n' "$config" >&2
    exit 1
fi
want=$(grep -oE 'age1[0-9a-z]+' "$config" | LC_ALL=C sort -u)
if [ -z "$want" ]; then
    printf 'check-sops-recipients: %s names no readers\n' "$config" >&2
    exit 1
fi

status=0
for repo in "$@"; do
    if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        printf 'check-sops-recipients: %s is not a checkout\n' "$repo" >&2
        status=1
        continue
    fi
    while IFS= read -r f; do
        case $f in
            *.yaml | *.yml) ;;
            *) continue ;;
        esac
        file=$repo/$f
        grep -q '^sops:' "$file" 2>/dev/null || continue
        have=$(grep -oE 'recipient: age1[0-9a-z]+' "$file" \
            | sed 's/^recipient: //' | LC_ALL=C sort -u)
        if [ "$have" = "$want" ]; then
            continue
        fi
        printf 'check-sops-recipients: %s does not match the canonical readers\n' "$f" >&2
        printf '  missing: %s\n' \
            "$(LC_ALL=C comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$have") | tr '\n' ' ')" >&2
        printf '  extra:   %s\n' \
            "$(LC_ALL=C comm -13 <(printf '%s\n' "$want") <(printf '%s\n' "$have") | tr '\n' ' ')" >&2
        status=1
    done < <(git -C "$repo" ls-files)
done
exit "$status"
