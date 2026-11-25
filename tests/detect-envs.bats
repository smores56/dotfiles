#!/usr/bin/env bats
# The machine-set inference, with fake uname, systemctl, and flatpak.
load helpers

setup() {
    bin=$BATS_TEST_TMPDIR/bin
    mkdir -p "$bin"
    printf '#!/bin/sh\nprintf "%%s\\n" "${FAKE_OS:-Linux}"\n' >"$bin/uname"
    # A headless cloud image reports graphical.target, so that alone must not
    # decide.
    cat >"$bin/systemctl" <<'EOF'
#!/bin/sh
case ${1-} in
    get-default) printf 'graphical.target\n' ;;
    is-enabled) [ "${FAKE_DM:-0}" = 1 ] ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$bin/uname" "$bin/systemctl"
}

# PATH holds only the fakes, so a host with flatpak installed cannot decide the
# headless case; sh is therefore invoked by path.
# infer <os> [DOTFILES_ENVS] [extra env...]
infer() {
    local os=$1 envs=${2:-} sh_bin
    shift 1
    shift $(($# > 0))
    sh_bin=$(command -v sh)
    env -i PATH="$bin" FAKE_OS="$os" DOTFILES_ENVS="$envs" "$@" \
        "$sh_bin" "$dotfiles_root/scripts/detect-envs.sh"
}

@test "a headless image defaulting to graphical.target is identity" {
    run infer Linux
    assert_success
    assert_output identity
}

@test "a display manager marks a Linux desktop" {
    run infer Linux '' FAKE_DM=1
    assert_success
    assert_output desktop,identity
}

@test "a display marks a Linux desktop" {
    run infer Linux '' DISPLAY=:0
    assert_success
    assert_output desktop,identity
}

@test "macOS is the work laptop" {
    run infer Darwin
    assert_success
    assert_output desktop,work
}

@test "DOTFILES_ENVS overrides the inference" {
    run infer Linux desktop,work
    assert_success
    assert_output desktop,work
}

@test "an unsupported system fails" {
    run infer FreeBSD
    assert_failure
}

@test "Flatpak marks a Linux desktop" {
    printf '#!/bin/sh\n' >"$bin/flatpak"
    chmod +x "$bin/flatpak"
    run infer Linux
    assert_success
    assert_output desktop,identity
}
