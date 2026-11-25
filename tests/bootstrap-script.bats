#!/usr/bin/env bats
# scripts/bootstrap.sh against a fixture remote that git reaches through
# url.insteadOf and a preinstalled fake mise, so nothing reaches the network.
load helpers

setup() {
    [ "$(uname -s)" != Darwin ] || skip "macOS keeps a normal clone"
    script=$dotfiles_root/scripts/bootstrap.sh
    home=$BATS_TEST_TMPDIR/home
    repos=$BATS_TEST_TMPDIR/root
    src=$BATS_TEST_TMPDIR/src
    remote=$BATS_TEST_TMPDIR/remote.git
    marker=$BATS_TEST_TMPDIR/marker
    mise_log=$BATS_TEST_TMPDIR/mise.log

    mkdir -p "$src/scripts" "$repos"
    printf '#!/bin/sh\ntouch "$BOOTSTRAP_MARKER"\n' >"$src/scripts/install-mise.sh"
    printf '#!/bin/sh\nln -sfn "$DOTFILES_CHECKOUT" "$DOTFILES_LINK"\n' \
        >"$src/scripts/link-dotfiles-checkout.sh"
    chmod +x "$src/scripts/install-mise.sh" "$src/scripts/link-dotfiles-checkout.sh"
    git -C "$src" init -q -b main
    git -C "$src" add -A
    git -C "$src" -c user.email=fixture@example.invalid -c user.name=fixture \
        commit -q -m fixture
    git clone -q --bare "$src" "$remote"

    # The clone needs no mise, so a fake one records any call as a failure.
    mkdir -p "$home/.local/bin"
    cat >"$home/.local/bin/mise" <<EOF
#!/bin/sh
printf '%s\\n' "\$*" >>"$mise_log"
exit 9
EOF
    chmod +x "$home/.local/bin/mise"

    repo=$repos/github.com/smores56/dotfiles
}

# run_bootstrap <home> <root> <checkout>: the script as a fresh login shell sees
# it, with the https remote redirected to the fixture and nothing else inherited.
run_bootstrap() {
    env -i HOME="$1" PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        BOOTSTRAP_ROOT="$2" BOOTSTRAP_CHECKOUT="$3" \
        BOOTSTRAP_REMOTE="https://github.com/smores56/dotfiles.git" \
        BOOTSTRAP_MARKER="$marker" \
        GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$remote.insteadOf" \
        GIT_CONFIG_VALUE_0=https://github.com/smores56/dotfiles.git \
        sh "$script"
}

# bootstrapped: the fresh-machine run, failing the calling test with the script's
# own output so a later assertion is never read against a half-built checkout.
bootstrapped() {
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_success
}

# a machine whose ~/.dotfiles is already a real directory, at a root of its own
real_checkout() {
    home=$BATS_TEST_TMPDIR/home2
    repos=$BATS_TEST_TMPDIR/root2
    mkdir -p "$home/.dotfiles"
}

# a force-push on origin that rewrites the history the worktree has
rewrite_origin() {
    printf 'rewritten\n' >"$src/rewritten"
    git -C "$src" add -A
    git -C "$src" -c user.email=fixture@example.invalid -c user.name=fixture \
        commit -q --amend --no-edit
    git -C "$src" push -q -f "$remote" HEAD:refs/heads/main
}

# --- a fresh machine, after the one sudo prompt that creates the root

@test "bootstrap exits 0 on a fresh machine" {
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_success
}

@test "the clone needs no mise" {
    bootstrapped
    run test -e "$mise_log"
    assert_failure
}

@test "the bare gitdir lands under the root" {
    bootstrapped
    run git -C "$repo" rev-parse --is-bare-repository
    assert_output true
}

@test "origin's branches are fetched as remote-tracking refs" {
    bootstrapped
    run git -C "$repo" rev-parse --verify -q refs/remotes/origin/main
    assert_success
}

@test "the default worktree is created" {
    bootstrapped
    run test -f "$repo/main/scripts/install-mise.sh"
    assert_success
}

@test "the fetch refspec is configured" {
    bootstrapped
    run git -C "$repo" config --get remote.origin.fetch
    assert_output '+refs/heads/*:refs/remotes/origin/*'
}

@test "main tracks origin/main" {
    bootstrapped
    run git -C "$repo/main" rev-parse --abbrev-ref --symbolic-full-name '@{u}'
    assert_output origin/main
}

@test '~/.dotfiles is a symlink to the main worktree' {
    bootstrapped
    run readlink "$home/.dotfiles"
    assert_output "$repo/main"
}

@test "the checkout's installer runs" {
    bootstrapped
    run test -e "$marker"
    assert_success
}

@test "a second bootstrap keeps the clone and succeeds" {
    bootstrapped
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_success
}

@test "the second bootstrap runs the installer again" {
    bootstrapped
    rm -f "$marker"
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_success
    run test -e "$marker"
    assert_success
}

# --- a machine that already has a real checkout

@test "bootstrap refuses an existing real checkout" {
    real_checkout
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_failure
}

@test "the existing checkout is still a real directory" {
    real_checkout
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_failure
    run test -d "$home/.dotfiles"
    assert_success
}

@test "the existing checkout was not replaced by a symlink" {
    real_checkout
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_failure
    run test -L "$home/.dotfiles"
    assert_failure
}

@test "nothing is cloned before the refusal" {
    real_checkout
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_failure
    run test -e "$repos/github.com"
    assert_failure
}

# --- a force-push on origin rewrote the history the worktree has

@test "a bootstrap after an upstream history rewrite exits 0" {
    bootstrapped
    rewrite_origin
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_success
}

@test "the worktree follows the rewritten origin/main" {
    bootstrapped
    rewrite_origin
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_success
    head=$(git -C "$repo/main" rev-parse HEAD)
    run git -C "$repo" rev-parse refs/remotes/origin/main
    assert_output "$head"
}

@test "the installer runs after converging" {
    bootstrapped
    rewrite_origin
    rm -f "$marker"
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_success
    run test -e "$marker"
    assert_success
}

# Uncommitted edits are the one thing a reset would silently lose.

@test "a bootstrap refuses a worktree with uncommitted changes" {
    bootstrapped
    printf '\n# local edit\n' >>"$repo/main/scripts/install-mise.sh"
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_failure
}

@test "the hand edit survives the refusal" {
    bootstrapped
    printf '\n# local edit\n' >>"$repo/main/scripts/install-mise.sh"
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_failure
    run grep -qF '# local edit' "$repo/main/scripts/install-mise.sh"
    assert_success
}

@test "the refused bootstrap never runs the installer" {
    bootstrapped
    printf '\n# local edit\n' >>"$repo/main/scripts/install-mise.sh"
    rm -f "$marker"
    run run_bootstrap "$home" "$repos" "$home/.dotfiles"
    assert_failure
    run test -e "$marker"
    assert_failure
}
