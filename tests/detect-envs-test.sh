#!/usr/bin/env bash
# The machine-set inference, with fake uname, systemctl, and flatpak.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

bin=$tmp/bin
mkdir -p "$bin"
printf '#!/bin/sh\nprintf "%%s\\n" "${FAKE_OS:-Linux}"\n' >"$bin/uname"
# A headless cloud image reports graphical.target, so that alone must not decide.
cat >"$bin/systemctl" <<'EOF'
#!/bin/sh
case ${1-} in
    get-default) printf 'graphical.target\n' ;;
    is-enabled) [ "${FAKE_DM:-0}" = 1 ] ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$bin/uname" "$bin/systemctl"

# PATH holds only the fakes, so a host with flatpak installed cannot decide the
# headless case; sh is therefore invoked by path.
sh_bin=$(command -v sh)
run() {  # run <os> [DOTFILES_ENVS] [extra env...]
    local os=$1 envs=${2:-}
    shift 1
    shift $(($# > 0))
    env -i PATH="$bin" FAKE_OS="$os" DOTFILES_ENVS="$envs" "$@" \
        "$sh_bin" "$root/scripts/detect-envs.sh"
}

expect "a headless image defaulting to graphical.target is identity" identity "$(run Linux)"
expect "a display manager marks a Linux desktop" desktop,identity "$(run Linux '' FAKE_DM=1)"
expect "a display marks a Linux desktop" desktop,identity "$(run Linux '' DISPLAY=:0)"
expect "macOS is the work laptop" desktop,work "$(run Darwin)"
expect "DOTFILES_ENVS overrides the inference" desktop,work "$(run Linux desktop,work)"
assert_not "an unsupported system fails" run FreeBSD

printf '#!/bin/sh\n' >"$bin/flatpak"
chmod +x "$bin/flatpak"
expect "Flatpak marks a Linux desktop" desktop,identity "$(run Linux)"

finish
