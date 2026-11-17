#!/usr/bin/env bash
# Behavioural tests for the machine-set inference, with fake uname/systemctl.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
expect() {  # expect <desc> <want> <got>
    if [ "$2" = "$3" ]; then ok "$1"; else no "$1 (want '$2', got '$3')"; fi
}

bin=$tmp/bin
mkdir -p "$bin"
printf '#!/bin/sh\nprintf "%%s\\n" "${FAKE_OS:-Linux}"\n' >"$bin/uname"
printf '#!/bin/sh\nprintf "%%s\\n" "${FAKE_TARGET:-multi-user.target}"\n' >"$bin/systemctl"
chmod +x "$bin/uname" "$bin/systemctl"

# PATH holds only the fakes: with the host's /usr/bin on it, a machine that
# happens to have flatpak installed would decide the headless case.
# `sh` is invoked by path: PATH holds only the fakes, so a host with flatpak
# installed cannot decide the headless case.
sh_bin=$(command -v sh)
run() {
    env -i PATH="$bin" FAKE_OS="$1" FAKE_TARGET="$2" \
        DOTFILES_ENVS="${3:-}" "$sh_bin" "$root/scripts/detect-envs.sh"
}

rm -f "$bin/flatpak"
expect "a headless Linux host is identity" identity "$(run Linux multi-user.target)"
expect "a graphical Linux host is desktop,identity" desktop,identity \
    "$(run Linux graphical.target)"

printf '#!/bin/sh\n' >"$bin/flatpak"
chmod +x "$bin/flatpak"
expect "Flatpak marks a Linux desktop" desktop,identity "$(run Linux multi-user.target)"

expect "a display marks a Linux desktop" desktop,identity \
    "$(env -i PATH="$bin" FAKE_OS=Linux FAKE_TARGET=multi-user.target DISPLAY=:0 \
        "$sh_bin" "$root/scripts/detect-envs.sh")"
expect "macOS is the work laptop" desktop,work "$(run Darwin multi-user.target)"
expect "DOTFILES_ENVS overrides the inference" desktop,work \
    "$(run Linux multi-user.target desktop,work)"

if run FreeBSD multi-user.target >/dev/null 2>&1; then
    no "an unsupported system fails"
else
    ok "an unsupported system fails"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
