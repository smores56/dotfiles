#!/bin/sh
# The canonical policy passes its own check, and every checkout that vendors a
# copy carries the same bytes. A missing sibling checkout is skipped: this test
# must pass on a lone clone too.
set -eu
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root" || exit 1

python3 scripts/sops-policy.py check --repo "$root"

for repo in "${HOMELAB_REPO:-/srv/git/github.com/smores56/homelab-platform/main}" \
            "${HOMELAB_APPS_REPO:-/srv/git/github.com/smores56/homelab-apps/main}"; do
    [ -d "$repo" ] || continue
    copy=$repo/scripts/sops-policy.py
    [ -f "$copy" ] || continue
    if ! cmp -s scripts/sops-policy.py "$copy"; then
        printf 'FAIL %s differs from the canonical policy\n' "$copy" >&2
        exit 1
    fi
done
