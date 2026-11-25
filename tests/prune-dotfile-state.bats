#!/usr/bin/env bats
# scripts/prune-dotfile-state.sh drops the links a checkout at another path left
# in mise's dotfile state. That state names the same targets as the live
# entries, so --prune-dotfiles deletes the live links and the next bootstrap
# recreates them: every other run left half the dotfiles unapplied.
load helpers

setup() {
    home=$BATS_TEST_TMPDIR/home
    state_home=$BATS_TEST_TMPDIR/state
    state=$state_home/mise/dotfiles
    # The script treats the checkout it lives in as the live one.
    live=$dotfiles_root/home/.config/gh
    mkdir -p "$home" "$state"
}

# prune <xdg-state-home>: prune against that state dir.
prune() {
    env -i HOME="$home" XDG_STATE_HOME="$1" \
        sh "$dotfiles_root/scripts/prune-dotfile-state.sh"
}

# record <dir> <name> <source> <target> <link:target>...
record() {
    dir=$1 name=$2 source=$3 target=$4
    shift 4
    mkdir -p "$dir"
    {
        printf 'version = 1\nsource = "%s"\ntarget = "%s"\n' "$source" "$target"
        for link in "$@"; do
            printf '\n[[links]]\nsource = "%s"\ntarget = "%s"\n' "${link%%:*}" "${link#*:}"
        done
    } >"$dir/$name.toml"
}

# State a checkout that moved twice leaves behind: a ghq clone and a ~/.dotfiles
# clone, one record whose links only partly collide with the live entries, and
# records the script must not touch.
seed_moved_checkout() {
    record "$state" live "$live" "$home/.config/gh" \
        "$live/config.yml:$home/.config/gh/config.yml"
    record "$state" ghq "$home/ghq/github.com/smores56/dotfiles/home/.config/gh" "$home/.config/gh" \
        "$home/ghq/github.com/smores56/dotfiles/home/.config/gh/config.yml:$home/.config/gh/config.yml"
    record "$state" dotfiles "$home/.dotfiles/home/.config/gh" "$home/.config/gh" \
        "$home/.dotfiles/home/.config/gh/config.yml:$home/.config/gh/config.yml" \
        "$home/.dotfiles/home/.config/gh/retired.yml:$home/.config/gh/retired.yml"
    record "$state" orphaned "$home/dotfiles/home/.config/removed" "$home/.config/removed" \
        "$home/dotfiles/home/.config/removed/x:$home/.config/removed/x"
    printf 'version = 1\ntarget = "%s"\n' "$home/.config/git/machine.inc" >"$state/nosource.toml"
    mkdir -p "$state/targets"
    printf 'version = 1\ntarget = "%s"\n' "$home/.config/git/machine.inc" >"$state/targets/rendered.toml"
}

# Assert the command printed nothing at all: bats keeps stderr out of $output.
assert_silent() {
    assert_equal "$output$stderr" ""
}

@test "a missing state dir is not an error and says nothing" {
    run --separate-stderr prune "$BATS_TEST_TMPDIR/absent"
    assert_success
    assert_silent
}

@test "the prune exits 0 and reports what it updated" {
    seed_moved_checkout
    run --separate-stderr prune "$state_home"
    assert_success
    assert_equal "$stderr" "dotfiles-state: updated 2 state file(s) from another checkout path"
}

@test "state from this checkout stays" {
    seed_moved_checkout
    run prune "$state_home"
    assert [ -f "$state/live.toml" ]
}

@test "state from a ghq checkout goes" {
    seed_moved_checkout
    run prune "$state_home"
    refute [ -e "$state/ghq.toml" ]
}

@test "a record that loses its only twin keeps the links nothing claims" {
    seed_moved_checkout
    run prune "$state_home"
    assert [ -f "$state/dotfiles.toml" ]
    assert_equal "$(grep -c '^\[\[links\]\]$' "$state/dotfiles.toml")" 1
    run grep -q 'retired.yml' "$state/dotfiles.toml"
    assert_success
    run grep -q 'config/gh/config.yml' "$state/dotfiles.toml"
    assert_failure
}

@test "state for a target nothing live claims stays" {
    seed_moved_checkout
    run prune "$state_home"
    assert [ -f "$state/orphaned.toml" ]
}

@test "state without a source is left alone" {
    seed_moved_checkout
    run prune "$state_home"
    assert [ -f "$state/nosource.toml" ]
}

@test "the targets index is left alone" {
    seed_moved_checkout
    run prune "$state_home"
    assert [ -f "$state/targets/rendered.toml" ]
}

@test "a second prune removes nothing and says nothing" {
    seed_moved_checkout
    run prune "$state_home"
    run --separate-stderr prune "$state_home"
    assert_success
    assert_silent
    assert [ -f "$state/live.toml" ]
}

# Nothing from this checkout is recorded yet, as on a machine whose checkout
# just moved: forgetting every record would lose prune's handle on retired
# groups, so the script leaves them for prune.
@test "a state dir with no live record keeps its records" {
    record "$BATS_TEST_TMPDIR/state2/mise/dotfiles" stale "$home/old/home/.config/gh" "$home/.config/gh" \
        "$home/old/home/.config/gh/config.yml:$home/.config/gh/config.yml"
    run --separate-stderr prune "$BATS_TEST_TMPDIR/state2"
    assert_success
    assert_silent
    assert [ -f "$BATS_TEST_TMPDIR/state2/mise/dotfiles/stale.toml" ]
}
