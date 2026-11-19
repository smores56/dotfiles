#!/usr/bin/env bash
# The machine-set inference, with fake uname and systemctl.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

bin=$tmp/bin
mkdir -p "$bin"
printf '#!/bin/sh\nprintf "%%s\\n" "${FAKE_OS:-Linux}"\n' >"$bin/uname"
printf '#!/bin/sh\nprintf "%%s\\n" "${FAKE_TARGET:-multi-user.target}"\n' >"$bin/systemctl"
chmod +x "$bin/uname" "$bin/systemctl"

# PATH holds only the fakes, so a host with flatpak installed cannot decide the
# headless case; sh is therefore invoked by path.
sh_bin=$(command -v sh)
run() {  # run <os> <target> [DOTFILES_ENVS] [extra env...]
    local os=$1 target=$2 envs=${3:-}
    shift 2
    shift $(($# > 0))
    env -i PATH="$bin" FAKE_OS="$os" FAKE_TARGET="$target" DOTFILES_ENVS="$envs" "$@" \
        "$sh_bin" "$root/scripts/detect-envs.sh"
}

expect "a headless Linux host is identity" identity "$(run Linux multi-user.target)"
expect "a graphical Linux host is desktop,identity" desktop,identity "$(run Linux graphical.target)"
expect "a display marks a Linux desktop" desktop,identity "$(run Linux multi-user.target '' DISPLAY=:0)"
expect "macOS is the work laptop" desktop,work "$(run Darwin multi-user.target)"
expect "DOTFILES_ENVS overrides the inference" desktop,work "$(run Linux multi-user.target desktop,work)"
assert_not "an unsupported system fails" run FreeBSD multi-user.target

printf '#!/bin/sh\n' >"$bin/flatpak"
chmod +x "$bin/flatpak"
expect "Flatpak marks a Linux desktop" desktop,identity "$(run Linux multi-user.target)"

finish
