#!/usr/bin/env bats
# The canonical policy passes its own check, and every checkout that vendors a
# copy carries the same bytes. A missing sibling checkout is skipped: this test
# must pass on a lone clone too.
load helpers

@test "the canonical policy passes and every vendored copy is byte-identical" {
    run python3 "$dotfiles_root/scripts/sops-policy.py" check --repo "$dotfiles_root"
    assert_success

    differing=''
    for repo in "${HOMELAB_REPO:-/srv/git/github.com/smores56/homelab-platform/main}" \
        "${HOMELAB_APPS_REPO:-/srv/git/github.com/smores56/homelab-apps/main}"; do
        copy=$repo/scripts/sops-policy.py
        [ -f "$copy" ] || continue
        cmp -s "$dotfiles_root/scripts/sops-policy.py" "$copy" || differing="$differing $copy"
    done
    assert_equal "$differing" ""
}
