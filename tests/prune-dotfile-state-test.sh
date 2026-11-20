#!/usr/bin/env bash
# scripts/prune-dotfile-state.sh drops the links a checkout at another path left
# in mise's dotfile state. That state names the same targets as the live
# entries, so --prune-dotfiles deletes the live links and the next bootstrap
# recreates them: every other run left half the dotfiles unapplied.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

script=$root/scripts/prune-dotfile-state.sh
home=$tmp/home
state=$tmp/state/mise/dotfiles
# The script treats the checkout it lives in as the live one.
live=$root/home/.config/gh

run() {  # run <xdg-state-home>: prune against that state dir
    env -i HOME="$home" XDG_STATE_HOME="$1" sh "$script" >"$tmp/out" 2>&1
    status=$?
}
said() { grep -q -- "$1" "$tmp/out"; }
record() {  # record <dir> <name> <source> <target> <link:target>...
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

mkdir -p "$home" "$state"

run "$tmp/state"
expect "a missing state dir is not an error" 0 "$status"
expect "a missing state dir says nothing" "" "$(cat "$tmp/out")"

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

run "$tmp/state"
expect "the prune exits 0" 0 "$status"
assert "state from this checkout stays" test -f "$state/live.toml"
assert_not "state from a ghq checkout goes" test -e "$state/ghq.toml"
assert "state whose only twin went is trimmed, not lost" test -f "$state/dotfiles.toml"
expect "the trimmed record keeps its one retired link" 1 \
    "$(grep -c '^\[\[links\]\]$' "$state/dotfiles.toml")"
assert "the retired link stays for prune" grep -q 'retired.yml' "$state/dotfiles.toml"
assert_not "the twin link is gone" grep -q 'config/gh/config.yml' "$state/dotfiles.toml"
assert "state for a target nothing live claims stays" test -f "$state/orphaned.toml"
assert "state without a source is left alone" test -f "$state/nosource.toml"
assert "the targets index is left alone" test -f "$state/targets/rendered.toml"
assert "the prune says what it updated" said "updated 2 state file"

run "$tmp/state"
expect "a second prune exits 0" 0 "$status"
expect "a second prune removes nothing and says nothing" "" "$(cat "$tmp/out")"
assert "the live state survives a second prune" test -f "$state/live.toml"

# Nothing from this checkout is recorded yet, as on a machine whose checkout
# just moved: forgetting every record would lose prune's handle on retired
# groups, so the script leaves them for prune.
record "$tmp/state2/mise/dotfiles" stale "$home/old/home/.config/gh" "$home/.config/gh" \
    "$home/old/home/.config/gh/config.yml:$home/.config/gh/config.yml"
run "$tmp/state2"
expect "a state dir with no live record exits 0" 0 "$status"
expect "a state dir with no live record says nothing" "" "$(cat "$tmp/out")"
assert "a state dir with no live record keeps its record" \
    test -f "$tmp/state2/mise/dotfiles/stale.toml"
