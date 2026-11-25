#!/bin/sh
# tests/tags.sh maps changed paths to the suites that cover them: one suite
# path per line, `all`, or nothing. A path no row claims is `all`, so a new
# file can never fall through to a green run that tested nothing.
#
# usage: tests/tags.sh [<path>...]
#        tests/tags.sh --changed [--base <ref>]
#        ... | tests/tags.sh
#
# Rows live in tests/tags.tsv: a tag names tests/<tag>.bats, `all` runs every
# suite, `none` runs none, and a suite's row names its own file.
set -u

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
            git -C "$root" diff --name-only "$compare" || exit 2
            git -C "$root" ls-files --others --exclude-standard || exit 2
        )
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

for path in $paths; do
    claimed=false
    claim=''
    while IFS=$tab read -r tag patterns || [ -n "$tag" ]; do
        case $tag in ''|'#'*) continue ;; esac
        for pattern in $patterns; do
            # shellcheck disable=SC2254 # the pattern is data from tags.tsv
            case $path in $pattern) claimed=true; claim=$tag ;; esac
        done
    done <"$root/tests/tags.tsv"
    if ! $claimed; then
        all=true
        continue
    fi
    case $claim in
        all) all=true ;;
        none) ;;
        *) add "$claim" ;;
    esac
done

if $all; then
    printf 'all\n'
    exit 0
fi
for tag in $tags; do
    printf 'tests/%s.bats\n' "$tag"
done
