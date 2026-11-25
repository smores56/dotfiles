#!/usr/bin/env bats
# The tree carries no secret material, no smortress key, no unpinned fish plugin,
# and nothing in fish startup or the shared env downloads.
load ../helpers

# Nothing here is a private key, stub or otherwise: the smortress key arrives
# from sops at mode 600 per machine, so a PEM or a PAT in the tree is a leak.
# The whole checkout, tracked or not: a key dropped at the root by an ad-hoc
# command is exactly what a managed-directories list misses.
@test "no secret material in the checkout" {
    secret_pattern='BEGIN [A-Z ]*PRIVATE KEY|AGE-SECRET-KEY-[A-Z0-9]|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'
    offenders=''
    for hit in $(grep -rIlE --exclude-dir=.git "$secret_pattern" "$dotfiles_root" 2>/dev/null); do
        offenders="$offenders $hit"
    done
    assert_equal "$offenders" ""
}

# Every tracked ciphertext carries exactly the canonical readers, and the
# canonical file names all five; a stale updatekeys or a missing key fails.
@test "sops ciphertexts match the canonical readers" {
    run bash "$dotfiles_root/scripts/check-sops-recipients.sh" "$dotfiles_root"
    assert_success
}

# The key is one file per machine, out of sops; nothing may ship a copy.
@test "the tree carries no smortress key" {
    run sh -c "test -e '$dotfiles_root/identity/.ssh/id_smortress' || test -e '$dotfiles_root/home/.ssh/id_smortress'"
    assert_failure
}

@test "every fish plugin repo is pinned to a full commit" {
    run sh -c "grep -E '^\"~/.local/share/fish-plugins/' '$dotfiles_root/mise.toml' | grep -vE 'ref = \"[0-9a-f]{40}\"( |,)'"
    assert_failure
}

@test "no downloader in fish startup or the shared env" {
    run grep -rnE 'curl|wget' "$dotfiles_root/home/.config/fish" "$dotfiles_root/home/.config/shell"
    assert_failure
}
