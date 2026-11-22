#!/usr/bin/env bash
# scripts/bootstrap.sh against a fixture remote that git reaches through
# url.insteadOf and a preinstalled fake mise, so nothing reaches the network.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

[ "$(uname -s)" != Darwin ] || skip_all "macOS keeps a normal clone"

script=$root/scripts/bootstrap.sh

mkdir -p "$tmp/src/scripts"
printf '#!/bin/sh\ntouch "$BOOTSTRAP_MARKER"\n' >"$tmp/src/scripts/install-mise.sh"
printf '#!/bin/sh\nln -sfn "$DOTFILES_CHECKOUT" "$DOTFILES_LINK"\n' \
    >"$tmp/src/scripts/link-dotfiles-checkout.sh"
chmod +x "$tmp/src/scripts/install-mise.sh" "$tmp/src/scripts/link-dotfiles-checkout.sh"
git -C "$tmp/src" init -q -b main
git -C "$tmp/src" add -A
git -C "$tmp/src" -c user.email=fixture@example.invalid -c user.name=fixture \
    commit -q -m fixture
git clone -q --bare "$tmp/src" "$tmp/remote.git"

# The clone needs no mise, so a fake one records any call as a failure.
mkdir -p "$tmp/home/.local/bin"
cat >"$tmp/home/.local/bin/mise" <<EOF
#!/bin/sh
printf '%s\\n' "\$*" >>"$tmp/mise.log"
exit 9
EOF
chmod +x "$tmp/home/.local/bin/mise"

run_bootstrap() {  # run_bootstrap <home> <root> <checkout>
    env -i HOME="$1" PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
        BOOTSTRAP_ROOT="$2" BOOTSTRAP_CHECKOUT="$3" \
        BOOTSTRAP_REMOTE="https://github.com/smores56/dotfiles.git" \
        BOOTSTRAP_MARKER="$tmp/marker" \
        GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.file://$tmp/remote.git.insteadOf" \
        GIT_CONFIG_VALUE_0=https://github.com/smores56/dotfiles.git \
        sh "$script"
}

# --- a fresh machine, after the one sudo prompt that creates the root

home=$tmp/home
repos=$tmp/root
mkdir -p "$repos"
assert "bootstrap exits 0 on a fresh machine" run_bootstrap "$home" "$repos" "$home/.dotfiles"
assert_not "the clone needs no mise" test -e "$tmp/mise.log"
repo=$repos/github.com/smores56/dotfiles
expect "the bare gitdir lands under the root" true "$(git -C "$repo" rev-parse --is-bare-repository)"
assert "origin's branches are fetched as remote-tracking refs" \
    git -C "$repo" rev-parse --verify -q refs/remotes/origin/main
assert "the default worktree is created" test -f "$repo/main/scripts/install-mise.sh"
expect "the fetch refspec is configured" '+refs/heads/*:refs/remotes/origin/*' \
    "$(git -C "$repo" config --get remote.origin.fetch)"
expect "main tracks origin/main" origin/main \
    "$(git -C "$repo/main" rev-parse --abbrev-ref --symbolic-full-name '@{u}')"
expect "$HOME/.dotfiles is a symlink to the main worktree" "$repo/main" "$(readlink "$home/.dotfiles")"
assert "the checkout's installer runs" test -e "$tmp/marker"

rm -f "$tmp/marker"
assert "a second bootstrap keeps the clone and succeeds" run_bootstrap "$home" "$repos" "$home/.dotfiles"
assert "the second bootstrap runs the installer again" test -e "$tmp/marker"

# --- a machine that already has a real checkout

home2=$tmp/home2
mkdir -p "$home2/.dotfiles"
assert_not "bootstrap refuses an existing real checkout" run_bootstrap "$home2" "$tmp/root2" "$home2/.dotfiles"
assert "the existing checkout is still a real directory" test -d "$home2/.dotfiles"
assert_not "the existing checkout was not replaced by a symlink" test -L "$home2/.dotfiles"
assert_not "nothing is cloned before the refusal" test -e "$tmp/root2/github.com"

# --- a force-push on origin rewrote the history the worktree has

printf 'rewritten\n' >"$tmp/src/rewritten"
git -C "$tmp/src" add -A
git -C "$tmp/src" -c user.email=fixture@example.invalid -c user.name=fixture \
    commit -q --amend --no-edit
git -C "$tmp/src" push -q -f "$tmp/remote.git" HEAD:refs/heads/main

rm -f "$tmp/marker"
assert "a bootstrap after an upstream history rewrite exits 0" \
    run_bootstrap "$home" "$repos" "$home/.dotfiles"
expect "the worktree follows the rewritten origin/main" \
    "$(git -C "$repo" rev-parse refs/remotes/origin/main)" \
    "$(git -C "$repo/main" rev-parse HEAD)"
assert "the installer runs after converging" test -e "$tmp/marker"

# Uncommitted edits are the one thing a reset would silently lose.
printf '\n# local edit\n' >>"$repo/main/scripts/install-mise.sh"
rm -f "$tmp/marker"
assert_not "a bootstrap refuses a worktree with uncommitted changes" \
    run_bootstrap "$home" "$repos" "$home/.dotfiles"
assert "the hand edit survives the refusal" \
    grep -qF '# local edit' "$repo/main/scripts/install-mise.sh"
assert_not "the refused bootstrap never runs the installer" test -e "$tmp/marker"

finish
