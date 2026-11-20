#!/bin/sh
# Drop the links a checkout at another path left in mise's dotfile state. The
# state dir keys every applied group by its source path, so a moved checkout
# leaves records naming the same targets as the live entries: --prune-dotfiles
# then deletes the links the live entries own, and the next bootstrap recreates
# them, so every other run undid half the dotfiles. Only links another record
# claims from this checkout are dropped; the rest of the record stays, because
# it is the handle prune uses to remove files no entry declares any more.
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
state=${XDG_STATE_HOME:-$HOME/.local/state}/mise/dotfiles

log() { printf 'dotfiles-state: %s\n' "$*" >&2; }

[ -d "$state" ] || exit 0

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

# The first `source`/`target` of a state file is the group's; the ones after
# [[links]] belong to individual links.
field() { sed -n "s/^$1 = \"\(.*\)\"\$/\1/p" "$2" | head -n 1; }

# Every path this checkout deploys, group targets and link targets alike: a
# stale record's links collide with these, and prune deletes the paths it names.
for file in "$state"/*.toml; do
    [ -f "$file" ] || continue
    source=$(field source "$file")
    case $source in "$root"/*) ;; *) continue ;; esac
    sed -n 's/^target = "\(.*\)"$/\1/p' "$file" >>"$work/live"
done
[ -s "$work/live" ] || exit 0

# drop_twins <file>: print the record without the link blocks whose target a
# live record claims. Exit 2 when it holds no such link, 1 when nothing is left
# of it.
drop_twins() {  # shellcheck disable=SC2016 # awk program, not shell
    awk -v live="$work/live" '
        BEGIN { while ((getline t < live) > 0) twin[t] = 1 }
        function flush() {
            if (!block) return
            if (dropped) any = 1
            else { kept = 1; out = out buf }
            block = 0; buf = ""; dropped = 0
        }
        /^\[\[links\]\]$/ { flush(); block = 1; buf = $0 "\n"; next }
        block {
            buf = buf $0 "\n"
            if ($0 ~ /^target = "/) {
                t = $0
                sub(/^target = "/, "", t)
                sub(/"$/, "", t)
                if (t in twin) dropped = 1
            }
            next
        }
        { header = header $0 "\n" }
        END {
            flush()
            if (!any) exit 2
            if (!kept) exit 1
            printf "%s%s", header, out
        }
    ' "$1"
}

changed=0
for file in "$state"/*.toml; do
    [ -f "$file" ] || continue
    source=$(field source "$file")
    case $source in
        ''|"$root"/*) continue ;;
    esac
    rc=0
    drop_twins "$file" >"$work/pruned" || rc=$?
    case $rc in
        0) cp -- "$work/pruned" "$file"; changed=$((changed + 1)) ;;
        1) rm -f -- "$file"; changed=$((changed + 1)) ;;
    esac
done

[ "$changed" -eq 0 ] || log "updated $changed state file(s) from another checkout path"
