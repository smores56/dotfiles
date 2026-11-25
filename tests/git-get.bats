#!/usr/bin/env bats
# The `git get` alias as the identity environment renders it, run against a
# fixture remote that git reaches through url.insteadOf under a throwaway root.
load helpers

setup_file() {
    if ! command -v mise >/dev/null 2>&1 && [ -z "${MISE_BIN:-}" ]; then
        export git_get_skip="mise not installed"
        return 0
    fi
    mise_bin=${MISE_BIN:-$(command -v mise)}
    export mise_bin
    h=$BATS_FILE_TMPDIR/home
    mkdir -p "$h/.ssh"
    # A failed apply is a real failure of the identity environment, not a
    # reason to skip: a skip here would report the suite green with no coverage.
    env -i HOME="$h" PATH=/usr/bin:/bin TERM=dumb MISE_ENV=identity \
        MISE_TRUSTED_CONFIG_PATHS="$dotfiles_root" MISE_YES=1 "$mise_bin" -C "$dotfiles_root" dot apply
    export h
    export alias_text
    alias_text=$(git config -f "$h/.config/git/machine.inc" alias.get)
}

setup() {
    [ -z "${git_get_skip:-}" ] || skip "$git_get_skip"
}

# A fixture remote with two branches, and a linked worktree to call from: every
# personal checkout is a linked worktree, where git exports GIT_DIR to aliases,
# so git get runs from inside one.
fixture() {
    repos=$BATS_TEST_TMPDIR/repos
    up=$BATS_TEST_TMPDIR/up
    git init -q -b main "$up"
    git -C "$up" -c user.name=t -c user.email=t@t commit -q --allow-empty -m one
    git -C "$up" branch feat
    mkdir -p "$BATS_TEST_TMPDIR/fake/o"
    git clone -q --bare "$up" "$BATS_TEST_TMPDIR/fake/o/r"
    git -C "$up" worktree add -q "$BATS_TEST_TMPDIR/caller" feat
    repo=$repos/github.com/o/r
}

# clone: git get o/r, failing the test with the clone's own output.
clone() {
    run get o/r
    assert_success
}

# get <args...>: the rendered alias, root and GitHub redirected.
get() {
    cd "$BATS_TEST_TMPDIR/caller" || return 1
    env -i HOME="$BATS_TEST_TMPDIR" PATH=/usr/bin:/bin GIT_CONFIG_NOSYSTEM=1 \
        GIT_CONFIG_COUNT=3 \
        GIT_CONFIG_KEY_0=alias.get GIT_CONFIG_VALUE_0="${alias_text//\/srv\/git/$repos}" \
        GIT_CONFIG_KEY_1="url.file://$BATS_TEST_TMPDIR/fake/.insteadOf" GIT_CONFIG_VALUE_1=https://github.com/ \
        GIT_CONFIG_KEY_2=user.email GIT_CONFIG_VALUE_2=t@t \
        git get "$@"
}

@test "identity applies" {
    assert [ -s "$h/.config/git/machine.inc" ]
}

@test "the alias clones under the personal root" {
    [[ $alias_text == *'d=/srv/git/github.com/'* ]]
}

@test "git get exits 0" {
    fixture
    run get o/r
    assert_success
}

@test "the gitdir is bare" {
    fixture
    clone
    run git -C "$repo" rev-parse --is-bare-repository
    assert_output true
}

@test "every remote branch is a remote-tracking ref" {
    fixture
    clone
    run git -C "$repo" for-each-ref --format='%(refname:short)' refs/remotes
    assert_output "origin/feat
origin/main"
}

@test "the default branch is checked out beside the gitdir" {
    fixture
    clone
    run git -C "$repo/main" branch --show-current
    assert_output main
}

@test "the default branch tracks origin" {
    fixture
    clone
    run git -C "$repo/main" rev-parse --abbrev-ref '@{u}'
    assert_output origin/main
}

@test "a later pull fast-forwards" {
    fixture
    clone
    git -C "$up" -c user.name=t -c user.email=t@t commit -q --allow-empty -m two
    git -C "$up" push -q "$BATS_TEST_TMPDIR/fake/o/r" main
    env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$BATS_TEST_TMPDIR/fake/.insteadOf" \
        GIT_CONFIG_VALUE_0=https://github.com/ git -C "$repo/main" pull -q --ff-only >/dev/null 2>&1
    run git -C "$repo/main" rev-list --count HEAD
    assert_output 2
}

@test "the clone holds only the gitdir and the default worktree" {
    fixture
    clone
    run ls -A "$repo"
    assert_output ".git
main"
}

@test "a second git get refuses the existing clone" {
    fixture
    clone
    run get o/r
    assert_failure
}

@test "the refusal leaves the checkout alone" {
    fixture
    clone
    run get o/r
    assert_failure
    run git -C "$repo/main" branch --show-current
    assert_output main
}

@test "git get with no repository fails" {
    fixture
    run -127 get
    assert_equal "$status" 127
}

@test "the failure names the usage" {
    fixture
    run get
    assert_output --partial 'usage: git get owner/repo'
}

@test "a failed git get creates nothing" {
    fixture
    clone
    run -127 get
    assert_equal "$status" 127
    run ls "$repos/github.com"
    assert_output "o"
}
