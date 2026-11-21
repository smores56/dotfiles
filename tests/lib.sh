# shellcheck shell=sh
# Sourced by every test. tmp is physical because git reports worktrees by their
# real path (/private/var on macOS).

# shellcheck disable=SC2034
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(cd -P -- "$(mktemp -d)" && pwd) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
indent() { sed 's/^/     /' >&2; }

# assert/assert_not <desc> <cmd...>: leave the command's output in $out and
# show it on failure.
assert() {
    local desc=$1
    shift
    if "$@" >"$tmp/.out" 2>&1; then ok "$desc"; else no "$desc"; indent <"$tmp/.out"; fi
    out=$(cat "$tmp/.out")
}
assert_not() {
    local desc=$1
    shift
    if "$@" >"$tmp/.out" 2>&1; then no "$desc"; indent <"$tmp/.out"; else ok "$desc"; fi
    out=$(cat "$tmp/.out")
}
expect() {  # expect <desc> <want> <got>
    if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$2', got '$3')"; fi
}
contains() {  # contains <desc> <needle> <haystack>
    case $3 in
        *"$2"*) ok "$1" ;;
        *) no "$1 (got '$3')" ;;
    esac
}

mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# A mise shim whose version is unset is on PATH but fails at exec. Treating it
# as installed turns one environment gap into a pile of misleading failures.
usable_shell() {  # usable_shell <shell>: print its path when it runs
    local bin
    bin=$(command -v "$1" 2>/dev/null) || return 1
    "$bin" -c ':' >/dev/null 2>&1 || return 1
    printf '%s\n' "$bin"
}

# A test that cannot run here exits 0 with this line, which check.sh reports as a skip.
skip_all() { printf 'skip all (%s)\n' "$*"; exit 0; }

finish() {
    printf '\n%d passed, %d failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ]
}
