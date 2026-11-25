#!/bin/sh
# tests/tags.sh maps changed paths to the suites that cover them: one suite
# path per line, `all`, or nothing. A path no row claims is `all`, so a new
# file can never fall through to a green run that tested nothing.
#
# usage: tests/tags.sh [<path>...]
#        tests/tags.sh --changed [--base <ref>]
#        ... | tests/tags.sh
#
# Rows live in tests/tags.tsv: a tag names tests/<tag>.bats, and `all` runs
# every suite while `none` runs none. Every row a path matches counts, in any
# order, so one path can select several suites.
set -uf

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tab=$(printf '\t')
base=origin/main
changed=false
paths=''

while [ $# -gt 0 ]; do
    case $1 in
        --changed) changed=true ;;
        --base) base=${2:?--base needs a ref}; shift ;;
        -*) printf 'usage: %s [--changed [--base <ref>]] [<path>...]\n' "$0" >&2; exit 2 ;;
        *) paths="$paths$1
" ;;
    esac
    shift
done

if [ -z "$paths" ]; then
    if $changed; then
        compare=$(git -C "$root" merge-base "$base" HEAD) || {
            printf 'tags: %s has no merge base with HEAD\n' "$base" >&2
            exit 2
        }
        paths=$(
            git -C "$root" diff --name-only "$compare" || exit 1
            git -C "$root" ls-files --others --exclude-standard || exit 1
        ) || exit 1
    else
        paths=$(cat)
    fi
fi

all=false
tags=''
add() {
    case " $tags " in
        *" $1 "*) ;;
        *) tags="$tags $1" ;;
    esac
}

# matches <path> <patterns...>: any pattern a row lists.
matches() {
    m_path=$1
    shift
    for pattern in "$@"; do
        # shellcheck disable=SC2254 # the pattern is data from tags.tsv
        case $m_path in $pattern) return 0 ;; esac
    done
    return 1
}

work=$(mktemp) || exit 1
trap 'rm -f "$work"' EXIT HUP INT TERM
printf '%s\n' "$paths" >"$work"

# A changed suite claims itself: tests/<tag>.bats.
self_tag() {
    case $1 in
        tests/*.bats) printf '%s\n' "${1#tests/}" | sed 's/\.bats$//' ;;
        *) return 1 ;;
    esac
}

while IFS= read -r path; do
    [ -n "$path" ] || continue
    claimed=false
    # A suite claims itself, but a row still decides: the `all` row must stay
    # sticky for a change to the harness's own test.
    if tag=$(self_tag "$path"); then
        add "$tag"
        claimed=true
    fi
    while IFS=$tab read -r tag patterns || [ -n "$tag" ]; do
        case $tag in ''|'#'*) continue ;; esac
        # shellcheck disable=SC2086 # a row lists its patterns space-separated
        matches "$path" $patterns || continue
        claimed=true
        case $tag in
            all) all=true ;;
            none) ;;
            *) add "$tag" ;;
        esac
    done <"$root/tests/tags.tsv"
    $claimed || all=true
done <"$work"

if $all; then
    printf 'all\n'
    exit 0
fi
for tag in $tags; do
    [ -f "$root/tests/$tag.bats" ] || continue
    printf 'tests/%s.bats\n' "$tag"
done
