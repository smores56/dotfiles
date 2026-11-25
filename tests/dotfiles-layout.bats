#!/usr/bin/env bats
# scripts/link-dotfiles-checkout.sh keeps ~/.dotfiles a symlink to the default
# worktree; it reports what it will not touch, exits 1 for it, and never moves or
# replaces anything.
load helpers

setup() {
    script=$dotfiles_root/scripts/link-dotfiles-checkout.sh
    home=$BATS_TEST_TMPDIR/home
    checkout=$BATS_TEST_TMPDIR/worktree/main
    mkdir -p "$home" "$checkout"
    : >"$checkout/.git"
}

# link <link-path>: run the script against it, leaving $output and $status.
link() {
    run env DOTFILES_LINK="$1" DOTFILES_CHECKOUT="$checkout" sh "$script"
}

# Two runs: the first creates the link, the second finds it correct.
link_twice() {
    link "$home/.dotfiles"
    link "$home/.dotfiles"
}

# A link the script did not create, and a directory where the link belongs.
foreign_link() {
    mkdir -p "$BATS_TEST_TMPDIR/other"
    ln -s "$BATS_TEST_TMPDIR/other" "$home/foreign"
}

directory_in_the_way() {
    mkdir -p "$home/real/inner"
}

unwritable_parent() {
    ro=$BATS_TEST_TMPDIR/ro
    mkdir -p "$ro"
    chmod 555 "$ro"
}

@test "creating the link exits 0" {
    link "$home/.dotfiles"
    assert_success
}

@test "creates the link to the worktree" {
    link "$home/.dotfiles"
    run readlink "$home/.dotfiles"
    assert_output "$checkout"
}

@test "a correct link exits 0" {
    link_twice
    assert_success
}

@test "leaves a correct link alone" {
    link_twice
    run readlink "$home/.dotfiles"
    assert_output "$checkout"
}

@test "a correct link is not relinked" {
    link_twice
    assert_output ""
}

@test "a foreign link exits 1" {
    foreign_link
    link "$home/foreign"
    assert_failure
}

@test "a foreign link is not replaced" {
    foreign_link
    link "$home/foreign"
    run readlink "$home/foreign"
    assert_output "$BATS_TEST_TMPDIR/other"
}

@test "a foreign link is reported" {
    foreign_link
    link "$home/foreign"
    assert_output --partial 'points at'
}

@test "a directory in the way exits 1" {
    directory_in_the_way
    link "$home/real"
    assert_failure
}

@test "a directory in the way is untouched" {
    directory_in_the_way
    link "$home/real"
    assert [ -d "$home/real" ]
    refute [ -L "$home/real" ]
}

@test "a directory in the way is reported" {
    directory_in_the_way
    link "$home/real"
    assert_output --partial 'not a symlink'
}

@test "an absent worktree exits 0" {
    checkout=$BATS_TEST_TMPDIR/missing/main
    link "$home/absent"
    assert_success
}

@test "nothing is linked when the worktree is absent" {
    checkout=$BATS_TEST_TMPDIR/missing/main
    link "$home/absent"
    refute [ -e "$home/absent" ]
}

@test "an absent worktree is reported" {
    checkout=$BATS_TEST_TMPDIR/missing/main
    link "$home/absent"
    assert_output --partial 'nothing to link'
}

@test "a target that is not a checkout exits 0" {
    checkout=$BATS_TEST_TMPDIR/empty/main
    mkdir -p "$checkout"
    link "$home/empty"
    assert_success
}

@test "nothing is linked when the target is not a checkout" {
    checkout=$BATS_TEST_TMPDIR/empty/main
    mkdir -p "$checkout"
    link "$home/empty"
    refute [ -e "$home/empty" ]
}

@test "a target that is not a checkout is reported" {
    checkout=$BATS_TEST_TMPDIR/empty/main
    mkdir -p "$checkout"
    link "$home/empty"
    assert_output --partial 'no checkout'
}

@test "an unwritable parent exits 1" {
    unwritable_parent
    link "$ro/.dotfiles"
    chmod 755 "$ro"
    assert_failure
}

@test "nothing is created under an unwritable parent" {
    unwritable_parent
    link "$ro/.dotfiles"
    chmod 755 "$ro"
    refute [ -e "$ro/.dotfiles" ]
}

@test "an unwritable parent is reported" {
    unwritable_parent
    link "$ro/.dotfiles"
    chmod 755 "$ro"
    assert_output --partial 'not writable'
}
