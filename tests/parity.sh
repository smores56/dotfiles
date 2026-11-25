#!/usr/bin/env bash
# Prove a converted suite kept its assertions: run the shell suite as it is on a
# base ref and the bats file that replaced it, and compare the passing counts.
#
# usage: tests/parity.sh tests/prune-dotfile-state [<base>]
#
# The old suite is read from the base ref, so this works after it is deleted
# from the tree. Exit codes and passing counts must match; the assertion texts
# are normalized and diffed for information, which is where a silently renamed
# assertion shows up.
#
# A conversion aid for #908; it stops being useful once the last shell suite is
# gone (#930 retires tests/check.sh).
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

name=${1:?usage: tests/parity.sh <suite path without extension> [<base>]}
base=${2:-origin/main}
new=$name.bats

[[ -f $new ]] || {
  printf 'parity: %s is not in the tree\n' "$new" >&2
  exit 2
}
# The suite being replaced is named either <name>.sh or <name>-test.sh.
if git cat-file -e "$base:$name-test.sh" 2>/dev/null; then
  old=$name-test.sh
elif git cat-file -e "$base:$name.sh" 2>/dev/null; then
  old=$name.sh
else
  printf 'parity: %s has no %s or %s-test.sh\n' "$base" "$name.sh" "$name" >&2
  exit 2
fi

work=$(mktemp -d)
trap 'rm -rf "$work"; git worktree remove --force "$work/tree" 2>/dev/null' EXIT

# The old suite checks the tree it shipped with, and some of its assertions look
# at sibling files, so it runs in a checkout of the base rather than in the tree
# the conversion already changed.
git worktree add -q --detach "$work/tree" "$base"
git show "$base:$old" >"$work/old.sh"
old_rc=0 new_rc=0
(cd "$work/tree" && bash "$old") >"$work/old.log" 2>&1 || old_rc=$?
bats "$new" >"$work/new.log" 2>&1 || new_rc=$?
names() {  # names <log>: the assertion texts, without the runner's prefix
  grep '^ok' "$1" | sed -E 's/^ok +([0-9]+ +)?//' | sort
}
old_ok=$(names "$work/old.log" | wc -l)
new_ok=$(names "$work/new.log" | wc -l)
diff -u <(names "$work/old.log") <(names "$work/new.log") >"$work/names.diff" || true

# A suite that only exits non-zero on failure prints no assertion of its own,
# and a suite that does not source tests/lib.sh has no assertion format this
# script can count (its tool may print `ok` lines of its own).
if ! grep -q 'tests/lib.sh' "$work/old.sh" || [[ $old_ok -eq 0 ]]; then
  printf 'parity: %s shell prints no count these can compare; exit codes: %s/%s\n' \
    "$name" "$old_rc" "$new_rc"
  [[ $old_rc -eq 0 && $new_rc -eq 0 ]] || exit 1
  exit 0
fi

printf 'parity: %s shell %s ok (exit %s), bats %s ok (exit %s)\n' \
  "$name" "$old_ok" "$old_rc" "$new_ok" "$new_rc"

# Names may legitimately differ: a helper-generated name in the shell suite
# ("exit status for link=...") becomes a real description. They are shown, not
# counted against the conversion.
if [[ -s $work/names.diff ]]; then
  printf 'parity: %s assertion names differ (expected where the conversion renames)\n' "$name"
  cat "$work/names.diff" >&2
fi

if [[ $old_rc -ne 0 || $new_rc -ne 0 || $old_ok -ne $new_ok ]]; then
  printf 'parity: MISMATCH; logs follow\n' >&2
  printf -- '--- %s ---\n' "$old" >&2
  cat "$work/old.log" >&2
  printf -- '--- %s ---\n' "$new" >&2
  cat "$work/new.log" >&2
  exit 1
fi
