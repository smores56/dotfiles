#!/usr/bin/env bash
# Behavioural tests for scripts/bootstrap.sh. Hermetic: a fixture remote that
# git reaches through url.insteadOf, and a preinstalled fake mise, so nothing
# reaches the network or installs.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
script=$root/scripts/bootstrap.sh

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
assert() {  # assert <desc> <command...>
    local desc=$1
    shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else no "$desc"; fi
}
assert_not() {
    local desc=$1
    shift
    if "$@" >/dev/null 2>&1; then no "$desc"; else ok "$desc"; fi
}

# --- fixture remote ---------------------------------------------------------

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

# --- fakes ------------------------------------------------------------------

mkdir -p "$tmp/home/.local/bin"
# A mise already installed, so bootstrap skips the network installer. The
# clone needs no mise, so the fake records any call as a failure.
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

# --- a fresh machine --------------------------------------------------------

home=$tmp/home
repos=$tmp/root
# The real script takes its one sudo prompt to create the root; the test runs
# after that step, with the directory already owned by the user.
mkdir -p "$repos"
if run_bootstrap "$home" "$repos" "$home/.dotfiles" >"$tmp/out" 2>&1; then
    ok "bootstrap exits 0 on a fresh machine"
else
    no "bootstrap exits 0 on a fresh machine"
    sed 's/^/     /' "$tmp/out" >&2
fi

assert_not "the clone needs no mise" test -e "$tmp/mise.log"
repo=$repos/github.com/smores56/dotfiles
assert "the bare gitdir lands under the root" \
    test "$(git -C "$repo" rev-parse --is-bare-repository)" = true
assert "origin's branches are fetched as remote-tracking refs" \
    git -C "$repo" rev-parse --verify -q refs/remotes/origin/main
assert "the default worktree is created" test -f "$repo/main/scripts/install-mise.sh"
assert "the fetch refspec is configured" \
    test "$(git -C "$repo" config --get remote.origin.fetch)" = '+refs/heads/*:refs/remotes/origin/*'
assert "main tracks origin/main" \
    test "$(git -C "$repo/main" rev-parse --abbrev-ref --symbolic-full-name '@{u}')" = origin/main
assert "$HOME/.dotfiles is a symlink to the main worktree" \
    test "$(readlink "$home/.dotfiles")" = "$repo/main"
assert "the checkout's installer runs" test -e "$tmp/marker"

rm -f "$tmp/marker"
if run_bootstrap "$home" "$repos" "$home/.dotfiles" >"$tmp/out-rerun" 2>&1; then
    ok "a second bootstrap keeps the clone and succeeds"
else
    no "a second bootstrap keeps the clone and succeeds"
    sed 's/^/     /' "$tmp/out-rerun" >&2
fi
assert "the second bootstrap runs the installer again" test -e "$tmp/marker"

# --- a machine that already has a real checkout -----------------------------

home2=$tmp/home2
mkdir -p "$home2/.dotfiles"
if run_bootstrap "$home2" "$tmp/root2" "$home2/.dotfiles" >"$tmp/out2" 2>&1; then
    no "bootstrap refuses an existing real checkout"
else
    ok "bootstrap refuses an existing real checkout"
fi
assert "the existing checkout is still a real directory" test -d "$home2/.dotfiles"
assert_not "the existing checkout was not replaced by a symlink" test -L "$home2/.dotfiles"
assert_not "nothing is cloned before the refusal" test -e "$tmp/root2/github.com"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
