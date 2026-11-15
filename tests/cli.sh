#!/usr/bin/env bash
# Behavioral tests for the repos, worktrees, and dev wrappers.
#
# Everything runs against throwaway repositories and a fake container engine:
# no network, no engine, and nothing outside $tmp is written. HOME, the global
# git config, and the checkout root are all redirected, so the operator's setup
# cannot change the result.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
REPOS=$root/dot_local/bin/executable_repos
WORKTREES=$root/dot_local/bin/executable_worktrees
DEV=$root/dot_local/bin/executable_dev

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
skip() { printf 'skip %s\n' "$*"; }
assert() {
    if "$@" >/dev/null 2>&1; then ok "$DESC"; else no "$DESC"; fi
}
assert_not() {
    if "$@" >/dev/null 2>&1; then no "$DESC"; else ok "$DESC"; fi
}
DESC=""

export HOME=$tmp/home
export XDG_CONFIG_HOME=$tmp/home/.config
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_PAGER=cat
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$tmp/bin"
git config --global init.defaultBranch main
git config --global user.name test
git config --global user.email test@example.com
git config --global commit.gpgsign false
git config --global tag.gpgsign false

# Fixture repository with one commit on main.
make_repo() {
    git init -q "$1"
    printf 'one\n' > "$1/file"
    git -C "$1" add file
    git -C "$1" commit -qm one
}

json_path() { printf '%s' "$1" | sed -n 's/.*"path":"\([^"]*\)".*/\1/p'; }

# --- repos get -------------------------------------------------------------

mkdir -p "$tmp/remotes/acme"
git init -q --bare "$tmp/remotes/acme/demo.git"
seed=$tmp/seed-demo
make_repo "$seed"
git -C "$seed" remote add origin "$tmp/remotes/acme/demo.git"
git -C "$seed" push -q origin main
git -C "$tmp/remotes/acme/demo.git" symbolic-ref HEAD refs/heads/main
# The wrapper builds ssh URLs; rewrite them to the local fixture remotes.
git config --global url."file://$tmp/remotes/".insteadOf "git@github.com:"

repos_root=$tmp/repo-root
checkout=$(REPOS_ROOT=$repos_root sh "$REPOS" get acme/demo 2>"$tmp/repos.err")
DESC="repos get prints the checkout path"
assert test -n "$checkout"
DESC="repos get checks out the default branch"
assert test -f "$checkout/file"
DESC="repos get keeps the clean-bare layout (<repo>/.git is a directory)"
assert test -d "$repos_root/github.com/acme/demo/.git"
DESC="the checkout's .git is a gitdir file"
assert test -f "$checkout/.git"
DESC="repos get sets branch.main.remote"
assert test "$(git -C "$checkout" config --get branch.main.remote)" = origin
DESC="repos get sets branch.main.merge"
assert test "$(git -C "$checkout" config --get branch.main.merge)" = refs/heads/main
git -C "$seed" commit -q --allow-empty -m second
git -C "$seed" push -q origin main
DESC="git pull works in a fresh checkout"
assert git -C "$checkout" pull --ff-only --quiet

for bad in ../evil -x/y acme/../repo a/b/c/d 'acme/de mo' 'acme/' './acme'; do
    DESC="repos get rejects $bad"
    assert_not env REPOS_ROOT="$repos_root" sh "$REPOS" get "$bad"
done
DESC="rejected refs leave nothing on disk"
assert_not test -e "$repos_root/github.com/evil"

DESC="a failed clone fails"
assert_not env REPOS_ROOT="$repos_root" sh "$REPOS" get acme/missing
DESC="a failed clone leaves no destination behind"
assert_not test -e "$repos_root/github.com/acme/missing"

# --- work flat root ---------------------------------------------------------
mkdir -p "$tmp/remotes/blitzy-ai"
git init -q --bare "$tmp/remotes/blitzy-ai/demo.git"
git -C "$seed" push -q "$tmp/remotes/blitzy-ai/demo.git" main
git -C "$tmp/remotes/blitzy-ai/demo.git" symbolic-ref HEAD refs/heads/main

work_flat=$tmp/work-flat
work_checkout=$(REPOS_ROOT=$repos_root REPOS_WORK_FLAT=$work_flat \
    REPOS_WORK_OWNERS=blitzy-ai sh "$REPOS" get blitzy-ai/demo 2>"$tmp/work.err")
DESC="repos get routes a work owner to the flat root"
assert test "$work_checkout" = "$work_flat/demo/main"
DESC="the flat work checkout has the default branch"
assert test -f "$work_checkout/file"
out=$(REPOS_ROOT=$repos_root REPOS_WORK_FLAT=$work_flat \
    REPOS_WORK_OWNERS=blitzy-ai sh "$REPOS" list)
case $out in
    *"$work_flat/demo"*) ok "repos list includes the flat work checkout" ;;
    *) no "repos list includes the flat work checkout" ;;
esac

# The same routing comes from git config, so a chezmoi-rendered machine needs
# no exported environment.
git config --global smores.workFlat "$work_flat"
git config --global smores.workOwners "blitzy-ai"
rm -rf "$work_flat/demo"
work_checkout=$(REPOS_ROOT=$repos_root sh "$REPOS" get blitzy-ai/demo 2>"$tmp/work.err")
DESC="repos get reads the flat root from git config"
assert test "$work_checkout" = "$work_flat/demo/main"

# GitHub names are case-insensitive; a flat root cannot hold both spellings.
rm -rf "$work_flat/demo"
mkdir -p "$work_flat/DEMO"
DESC="repos get refuses a case-insensitive flat collision"
assert_not env REPOS_ROOT="$repos_root" sh "$REPOS" get blitzy-ai/demo
rm -rf "$work_flat/DEMO"
git config --global --unset smores.workFlat
git config --global --unset smores.workOwners

# --- worktrees new / prune -------------------------------------------------

seed=$tmp/seed-wt
make_repo "$seed"
git init -q --bare "$tmp/wt-remote.git"
git -C "$seed" remote add origin "$tmp/wt-remote.git"
git -C "$seed" push -q origin main
wt_repo=$tmp/wt-repo
git clone -q "$tmp/wt-remote.git" "$wt_repo"

json=$(cd "$wt_repo" && sh "$WORKTREES" new --slug demo 2>/dev/null)
wt=$(json_path "$json")
DESC="worktrees new creates the worktree"
assert test -d "$wt"
DESC="worktrees new reports branch and path"
assert test "$json" = "{\"branch\":\"smores/demo\",\"path\":\"$wt\",\"ticket\":null,\"base\":\"origin/main\"}"

(cd "$wt" && printf 'two\n' > two && git add two && git commit -qm two) >/dev/null 2>&1
git -C "$wt_repo" merge -q --no-ff smores/demo -m merge
git -C "$wt_repo" push -q origin main
git -C "$wt_repo" tag local-only

# fetch.pruneTags=true is the setting that used to delete local tags; the
# wrappers must not inherit that behaviour.
git -C "$wt_repo" config fetch.pruneTags true

out=$(cd "$wt_repo" && sh "$WORKTREES" prune 2>&1)
DESC="prune is a dry run by default"
assert test -d "$wt"
case $out in
    *would-remove*) ok "prune reports would-remove in a dry run" ;;
    *) no "prune reports would-remove in a dry run" ;;
esac
DESC="a dry run keeps the merged branch"
assert git -C "$wt_repo" rev-parse -q --verify refs/heads/smores/demo

(cd "$wt_repo" && sh "$WORKTREES" prune --apply) >/dev/null 2>&1
DESC="prune --apply removes a merged worktree"
assert_not test -e "$wt"
DESC="prune --apply removes the merged branch"
assert_not git -C "$wt_repo" rev-parse -q --verify refs/heads/smores/demo
DESC="prune keeps local-only tags even with fetch.pruneTags=true"
assert git -C "$wt_repo" rev-parse -q --verify refs/tags/local-only

# Two branches whose old `tr '/' '-'` spelling is identical must still get
# separate worktree paths.
collision_repo=$tmp/collision-repo
make_repo "$collision_repo"
git -C "$collision_repo" config smores.branchTemplate '{type}/{slug}'
coll_json=$(cd "$collision_repo" && sh "$WORKTREES" new --type feat --slug foo-bar 2>/dev/null)
coll_path=$(json_path "$coll_json")
coll_json2=$(cd "$collision_repo" && sh "$WORKTREES" new --type feat-foo --slug bar 2>/dev/null)
coll_path2=$(json_path "$coll_json2")
DESC="worktree paths do not collide across slash positions"
assert test "$coll_path" != "$coll_path2"
DESC="both colliding branches got a worktree"
assert test -d "$coll_path"
DESC="the second colliding branch got a worktree"
assert test -d "$coll_path2"

# Unmerged work: the branch has commits the default branch never saw.
json=$(cd "$wt_repo" && sh "$WORKTREES" new --slug unmerged 2>/dev/null)
wtu=$(json_path "$json")
(cd "$wtu" && printf 'x\n' > x && git add x && git commit -qm x) >/dev/null 2>&1
(cd "$wt_repo" && sh "$WORKTREES" prune --apply) >/dev/null 2>&1
DESC="prune keeps an unmerged worktree"
assert test -d "$wtu"
DESC="prune keeps an unmerged branch"
assert git -C "$wt_repo" rev-parse -q --verify refs/heads/smores/unmerged

# Dirty worktree whose commits are merged: removing it would discard work.
json=$(cd "$wt_repo" && sh "$WORKTREES" new --slug dirty 2>/dev/null)
wtd=$(json_path "$json")
(cd "$wtd" && git commit -q --allow-empty -m dirty && printf 'dirty\n' > dirty) >/dev/null 2>&1
git -C "$wt_repo" merge -q --no-ff smores/dirty -m merge-dirty
git -C "$wt_repo" push -q origin main
(cd "$wt_repo" && sh "$WORKTREES" prune --apply) >/dev/null 2>&1
DESC="prune keeps a dirty worktree"
assert test -d "$wtd"

# Content already in main but not an ancestor: only --force may delete it.
git -C "$wt_repo" checkout -q -b smores/cherry main
printf 'cherry\n' > "$wt_repo/cherry"
git -C "$wt_repo" add cherry
git -C "$wt_repo" commit -qm cherry
git -C "$wt_repo" checkout -q main
# An unrelated commit first, so the cherry-picked commit cannot come out with
# the same object id as the branch's commit (identical parents, tree, dates).
git -C "$wt_repo" commit -q --allow-empty -m after-branch
git -C "$wt_repo" cherry-pick smores/cherry >/dev/null 2>&1
git -C "$wt_repo" push -q origin main
wtx=$wt_repo/.worktrees/cherry
git -C "$wt_repo" worktree add -q "$wtx" smores/cherry
(cd "$wt_repo" && sh "$WORKTREES" prune --apply) >/dev/null 2>&1
DESC="prune keeps a content-integrated branch without --force"
assert test -d "$wtx"
DESC="prune never uses -D implicitly"
assert git -C "$wt_repo" rev-parse -q --verify refs/heads/smores/cherry
(cd "$wt_repo" && sh "$WORKTREES" prune --apply --force) >/dev/null 2>&1
DESC="prune --force removes a content-integrated worktree"
assert_not test -e "$wtx"
DESC="prune --force removes a content-integrated branch"
assert_not git -C "$wt_repo" rev-parse -q --verify refs/heads/smores/cherry

# The worktree prune runs from must never be removed.
json=$(cd "$wt_repo" && sh "$WORKTREES" new --slug current 2>/dev/null)
wtc=$(json_path "$json")
(cd "$wtc" && git commit -q --allow-empty -m current) >/dev/null 2>&1
git -C "$wt_repo" merge -q --no-ff smores/current -m merge-current
git -C "$wt_repo" push -q origin main
out=$(cd "$wtc" && sh "$WORKTREES" prune --apply 2>&1)
DESC="prune skips the current worktree"
assert test -d "$wtc"
case $out in
    *'current worktree'*) ok "prune explains why the current worktree is kept" ;;
    *) no "prune explains why the current worktree is kept" ;;
esac

# Age comes from the per-worktree gitdir, not the shared common dir: an old
# repository with a fresh worktree must survive --min-age.
if touch -d '2 hours ago' "$tmp" 2>/dev/null; then
    age_repo=$tmp/age-repo
    make_repo "$age_repo"
    json=$(cd "$age_repo" && sh "$WORKTREES" new --slug old 2>/dev/null)
    wta=$(json_path "$json")
    (cd "$wta" && git commit -q --allow-empty -m old) >/dev/null 2>&1
    git -C "$age_repo" merge -q --no-ff smores/old -m merge-old
    touch -d '2 hours ago' "$age_repo/.git"
    out=$(cd "$age_repo" && sh "$WORKTREES" prune --apply --min-age 1h 2>&1)
    DESC="prune measures age from the per-worktree gitdir"
    assert test -d "$wta"
    case $out in
        *younger*) ok "prune reports a worktree younger than --min-age" ;;
        *) no "prune reports a worktree younger than --min-age" ;;
    esac
    touch -d '2 hours ago' "$(git -C "$wta" rev-parse --absolute-git-dir)"
    (cd "$age_repo" && sh "$WORKTREES" prune --apply --min-age 1h) >/dev/null 2>&1
    DESC="prune removes an aged merged worktree"
    assert_not test -e "$wta"
else
    skip "worktree age tests (touch -d unsupported)"
fi

# A branch whose worktree is gone and whose reflog is gone has no evidence it
# is stale, so it is left alone.
nr_repo=$tmp/noreflog-repo
make_repo "$nr_repo"
git -C "$nr_repo" branch smores/noreflog main
rm -rf "$nr_repo/.git/logs/refs/heads/smores"
(cd "$nr_repo" && sh "$WORKTREES" prune --apply) >/dev/null 2>&1
DESC="prune keeps a branch-only ref with no reflog evidence"
assert git -C "$nr_repo" rev-parse -q --verify refs/heads/smores/noreflog

# No origin/HEAD, no main, no master: there is nothing to prune against.
trunk_repo=$tmp/trunk-repo
git init -q -b trunk "$trunk_repo"
printf 't\n' > "$trunk_repo/t"
git -C "$trunk_repo" add t
git -C "$trunk_repo" commit -qm t
git -C "$trunk_repo" worktree add -q "$trunk_repo/.worktrees/feature" -b feature trunk
out=$(cd "$trunk_repo" && sh "$WORKTREES" prune --apply 2>&1)
status=$?
DESC="prune with no default branch succeeds without deleting"
assert test "$status" -eq 0
DESC="prune with no default branch keeps the worktree"
assert test -d "$trunk_repo/.worktrees/feature"
case $out in
    *'no default branch'*) ok "prune says why it did nothing" ;;
    *) no "prune says why it did nothing" ;;
esac

# --- dev -------------------------------------------------------------------

fake=$tmp/bin
cat > "$fake/engine" <<'EOF'
#!/bin/sh
{
    printf '=== invocation\n'
    for arg in "$@"; do printf '%s\n' "$arg"; done
} >> "$DEV_FAKE_LOG"
exit 0
EOF
chmod +x "$fake/engine"
cp "$fake/engine" "$fake/podman"
chmod +x "$fake/podman"

printf '[user]\n\tname = test\n' > "$HOME/.gitconfig"
mkdir -p "$HOME/.config/git"
dev_repo=$tmp/dev-repo
git init -q "$dev_repo"
printf 'FROM scratch\n' > "$dev_repo/Containerfile"

export DEV_FAKE_LOG=$tmp/dev.log
agent_sock=$tmp/agent.sock
# A run block is everything after the last "=== invocation" marker.
run_block() { awk '/^=== invocation/{n++} n>=2' "$DEV_FAKE_LOG"; }
in_run() { run_block | grep -qxF -- "$1"; }
in_run_sub() { run_block | grep -qF -- "$1"; }

: > "$DEV_FAKE_LOG"
(cd "$dev_repo" && PATH="$fake:$PATH" DEV_ENGINE=engine GH_TOKEN=ghp_secret \
    GITHUB_TOKEN=ghs_secret SSH_AUTH_SOCK=$agent_sock DEV_SSH_AGENT=1 sh "$DEV") >/dev/null 2>&1

DESC="dev does not start a probe container"
assert test "$(grep -c '^=== invocation' "$DEV_FAKE_LOG")" -eq 2
DESC="dev passes no tty flags without a terminal"
assert_not in_run -i
DESC="dev passes no -t without a terminal"
assert_not in_run -t
DESC="dev mounts the global git config read-only"
assert in_run_sub "$HOME/.gitconfig:/home/dev/.gitconfig:ro"
DESC="dev mounts ~/.config/git read-only"
assert in_run_sub "$HOME/.config/git:/home/dev/.config/git:ro"
DESC="dev forwards the SSH agent socket"
assert in_run_sub "$agent_sock:$agent_sock"
DESC="dev exports SSH_AUTH_SOCK"
assert in_run "SSH_AUTH_SOCK=$agent_sock"
DESC="dev never mounts ~/.ssh"
assert_not in_run_sub '/.ssh'
DESC="dev never passes GH_TOKEN or GITHUB_TOKEN"
assert_not in_run_sub GH_TOKEN
DESC="dev never passes GITHUB_TOKEN"
assert_not in_run_sub GITHUB_TOKEN
DESC="dev trusts only the checkout's mise config"
assert in_run "MISE_TRUSTED_CONFIG_PATHS=$dev_repo"
DESC="dev does not trust every path"
assert_not in_run MISE_TRUSTED_CONFIG_PATHS=/
DESC="dev keeps mise installs on a per-repo volume"
assert_not in_run dev-mise:/home/dev/.local/share/mise
DESC="dev mounts a per-repo mise volume"
assert in_run_sub :/home/dev/.local/share/mise
DESC="dev runs no shell probe inside the image"
assert_not in_run -c

: > "$DEV_FAKE_LOG"
(cd "$dev_repo" && PATH="$fake:$PATH" DEV_ENGINE=podman GH_TOKEN=ghp_secret \
    SSH_AUTH_SOCK=$agent_sock sh "$DEV") >/dev/null 2>&1
DESC="dev relabels the git config for SELinux on podman"
assert in_run_sub "$HOME/.gitconfig:/home/dev/.gitconfig:ro,Z"
DESC="dev relabels the git config directory for SELinux"
assert in_run_sub "$HOME/.config/git:/home/dev/.config/git:ro,Z"
DESC="dev maps the host uid on podman"
assert in_run --userns=keep-id:uid=1000,gid=1000
DESC="dev still passes no token on podman"
assert_not in_run_sub GH_TOKEN

if script -qec true /dev/null >/dev/null 2>&1; then
    tty_wrapper=$tmp/tty-dev.sh
    {
        printf '#!/bin/sh\n'
        printf 'cd %s || exit 1\n' "$(printf '%q' "$dev_repo")"
        printf 'exec sh %s\n' "$(printf '%q' "$DEV")"
    } > "$tty_wrapper"
    chmod +x "$tty_wrapper"
    : > "$DEV_FAKE_LOG"
    PATH="$fake:$PATH" DEV_ENGINE=engine script -qec "$tty_wrapper" /dev/null >/dev/null 2>&1
    DESC="dev allocates a tty when one is attached"
    assert in_run -t
    DESC="dev keeps stdin open when a tty is attached"
    assert in_run -i
else
    skip "dev tty flags (script -qec unavailable)"
fi

printf '\n%d checks, %d failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
