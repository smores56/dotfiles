#!/bin/sh
# Checks the source tree: every script parses, every config loads, the guards
# hold, and the behavioural tests pass.
#
# usage: tests/check.sh [--shellcheck] [--changed [BASE]]
#
# --changed runs only the behavioural tests the changed paths need, using
# origin/main as the base unless one is named. Static checks always run.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

check_start=$(date +%s)
use_shellcheck=false
changed=false
base=origin/main
while [ $# -gt 0 ]; do
    case $1 in
        --shellcheck) use_shellcheck=true ;;
        --changed) changed=true
                   if [ $# -gt 1 ]; then
                       case $2 in -*) ;; *) base=$2; shift ;; esac
                   fi ;;
        --changed=*) changed=true; base=${1#--changed=} ;;
        *) printf 'usage: %s [--shellcheck] [--changed [BASE]]\n' "$0" >&2; exit 2 ;;
    esac
    shift
done

skip() { printf 'skip %s\n' "$*"; }
rel() { printf '%s' "${1#"$root"/}"; }
has() { command -v "$1" >/dev/null 2>&1; }

# --changed narrows the behavioural tests; the static checks are cheap and
# always run. An unclaimed path selects everything (tests/tags.sh).
selected_tests=all
if $changed; then
    git -C "$root" rev-parse --verify -q "$base^{commit}" >/dev/null || {
        printf 'check: no such base %s\n' "$base" >&2
        exit 2
    }
    # Compare from the merge base: a branch behind main must not select the
    # tests for commits it does not contain.
    compare=$(git -C "$root" merge-base "$base" HEAD) || {
        printf 'check: %s has no merge base with HEAD\n' "$base" >&2
        exit 2
    }
    changed_list=$tmp/changed
    { git -C "$root" diff --name-only "$compare" || exit 2
      git -C "$root" ls-files --others --exclude-standard || exit 2; } >"$changed_list"
    selected_tests=$(sh "$root/tests/tags.sh" <"$changed_list")
    printf 'changed against %s: %s\n' "$base" "${selected_tests:-none}"
fi
selected() {  # selected <suite name>: one path per line from tests/tags.sh
    [ "$selected_tests" = all ] && return 0
    printf '%s\n' "$selected_tests" | grep -qxF -e "tests/$1.bats" -e "tests/$1-test.sh"
}

# The syntax assertions live in tests/statics/syntax.bats; this list only feeds
# --shellcheck below.

shell_scripts() {
    for script in "$root"/home/.config/shell/env.sh "$root"/work/.config/shell/env.d/*.sh \
            "$root"/home/.local/bin/* "$root"/desktop/.local/bin/* \
            "$root"/scripts/*.sh "$root"/tests/*.sh "$root"/tests/*.bash "$root"/.githooks/*; do
        [ -f "$script" ] || continue
        case $(head -n 1 "$script") in
            *python*) ;;
            *bash*) printf 'bash %s\n' "$script" ;;
            *) printf 'sh %s\n' "$script" ;;
        esac
    done
}

shell_scripts >"$tmp/scripts"

# --- behavioural tests

if has git && has bash; then
    for test_script in "$root"/tests/*-test.sh; do
        [ -f "$test_script" ] || continue
        name=$(rel "$test_script")
        selected "$(basename -- "$test_script" -test.sh)" || continue
        if bash "$test_script" >"$tmp/test.log" 2>&1; then
            if grep -q '^skip all' "$tmp/test.log"; then
                skip "behavioral tests ($name: $(sed -n 's/^skip all (\(.*\))$/\1/p' "$tmp/test.log"))"
            else
                ok "behavioral tests ($name)"
            fi
        else
            no "behavioral tests ($name)"
            indent <"$tmp/test.log"
        fi
    done
else
    skip "behavioral tests (git or bash not installed)"
fi

# bats is a pinned tool: a missing or dangling shim fails rather than skips,
# because a skip here would report a migrated suite as green with no coverage.
if ! has bats; then
    no "bats suites (bats not installed; run mise install)"
elif ! bats --version >/dev/null 2>&1; then
    no "bats suites (bats is on PATH but does not run; run mise install)"
else
    for suite in "$root"/tests/*.bats; do
        [ -f "$suite" ] || continue
        name=$(rel "$suite")
        selected "$(basename -- "$suite" .bats)" || continue
        if ! bats "$suite" >"$tmp/suite.log" 2>&1; then
            no "bats suites ($name)"
            indent <"$tmp/suite.log"
        elif ! grep -q '^ok' "$tmp/suite.log"; then
            no "bats suites ($name: no tests ran)"
            indent <"$tmp/suite.log"
        elif [ "$(grep -c '^ok' "$tmp/suite.log")" = "$(grep -c '^ok.*# skip' "$tmp/suite.log")" ]; then
            skip "bats suites ($name: every test skipped)"
        else
            ok "bats suites ($name)"
        fi
    done
    # The static checks are one file per section under tests/statics/ and run on
    # every gate, --changed included: they are cheap greps over the checkout.
    for suite in "$root"/tests/statics/*.bats; do
        [ -f "$suite" ] || continue
        name=$(rel "$suite")
        if ! bats "$suite" >"$tmp/suite.log" 2>&1; then
            no "static checks ($name)"
            indent <"$tmp/suite.log"
        elif ! grep -q '^ok' "$tmp/suite.log"; then
            no "static checks ($name: no tests ran)"
            indent <"$tmp/suite.log"
        elif [ "$(grep -c '^ok' "$tmp/suite.log")" = "$(grep -c '^ok.*# skip' "$tmp/suite.log")" ]; then
            skip "static checks ($name: every test skipped)"
        else
            ok "static checks ($name)"
        fi
    done
fi

# --- optional shellcheck

if $use_shellcheck; then
    if has shellcheck; then
        # SC3043: `local` is not POSIX, but every real /bin/sh implements it.
        while read -r dialect script; do
            assert "shellcheck $(rel "$script")" \
                sh -c 'cd "$1" && shellcheck -x -s "$2" -S warning -e SC3043 "$3"' sh "$root" "$dialect" "$script"
        done <"$tmp/scripts"
    else
        skip "shellcheck (not installed)"
    fi
fi

printf '\n%d checks in %ss\n' "$((pass + fail))" "$(( $(date +%s) - check_start ))"
finish
