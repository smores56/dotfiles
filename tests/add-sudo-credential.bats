#!/usr/bin/env bats
# The sudo credential loader: every handle goes in, a .pub never does, and a
# missing agent or missing handle is a log line rather than a failure.
load helpers

setup() {
    command -v python3 >/dev/null 2>&1 || skip "python3 is not installed to make an agent socket"
    loader=$dotfiles_root/scripts/add-sudo-credential.sh
    bin=$BATS_TEST_TMPDIR/bin
    log=$BATS_TEST_TMPDIR/ssh-add.log
    os_file=$BATS_TEST_TMPDIR/os
    loaded=$BATS_TEST_TMPDIR/loaded
    mkdir -p "$bin"
    # Both agents bind the same socket, so the test is what decides the platform.
    printf '%s\n' Darwin >"$os_file"
    cat >"$bin/uname" <<'EOF'
#!/bin/sh
cat "$SSH_TEST_OS"
EOF
    # ssh-add records its argv, and `-L` reports whatever the case staged.
    cat >"$bin/ssh-add" <<'EOF'
#!/bin/sh
printf '%s provider=%s\n' "$*" "${SSH_SK_PROVIDER:-none}" >>"$SSH_ADD_LOG"
[ "${1:-}" = -L ] && [ -n "$SSH_ADD_LOADED" ] && cat "$SSH_ADD_LOADED"
exit 0
EOF
    chmod 755 "$bin/uname" "$bin/ssh-add"
}

# new_home <name>: a HOME with a bound agent socket
new_home() {
    home=$BATS_TEST_TMPDIR/$1
    mkdir -p "$home/.local/state/ssh" "$home/.ssh"
    python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' \
        "$home/.local/state/ssh/agent.sock"
}

# handle <file>: a private handle and its public half, in $home
handle() {
    : >"$home/.ssh/$1"
    # Distinct blobs: two handles are different credentials, and the loader
    # compares the key material to decide what is already in the agent.
    printf 'sk-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5%s %s\n' "$1" "$1" >"$home/.ssh/$1.pub"
}

# run_loader [file of loaded keys]: the loader against $home, logging to $log
run_loader() {
    : >"$log"
    env -i HOME="$home" PATH="$bin:/usr/bin:/bin" SSH_TEST_OS="$os_file" \
        SSH_ADD_LOG="$log" SSH_ADD_LOADED="${1:-}" sh "$loader"
}

# One credential per YubiKey, as enrollment mints them: a tap on the spare has to
# work too, and the agent only offers what was added.
@test "every enrolled handle is added and no public half is" {
    new_home three
    handle id_smortress_sudo_1
    handle id_smortress_sudo_2
    handle id_smortress_sudo_3
    run run_loader
    assert_success
    assert_equal "$(grep -c 'id_smortress_sudo_[123] ' "$log")" 3
    run grep -q '\.pub' "$log"
    assert_failure
}

# A handle already in the agent must not be added again, but the other two are
# the whole point of the per-key naming: a spare key's tap has to work.
@test "the missing handles are added but the loaded one is not" {
    new_home three
    handle id_smortress_sudo_1
    handle id_smortress_sudo_2
    handle id_smortress_sudo_3
    cat "$home/.ssh/id_smortress_sudo_1.pub" >"$loaded"
    run run_loader "$loaded"
    assert_success
    assert_equal "$(grep -c 'id_smortress_sudo_' "$log")" 2
    run grep -q 'id_smortress_sudo_1 ' "$log"
    assert_failure
}

# All three loaded is the steady state, and a second bootstrap must be silent.
@test "nothing is added when every handle is loaded" {
    new_home three
    handle id_smortress_sudo_1
    handle id_smortress_sudo_2
    handle id_smortress_sudo_3
    cat "$home"/.ssh/id_smortress_sudo_*.pub >"$loaded"
    run run_loader "$loaded"
    assert_success
    assert_equal "$(grep -c 'id_smortress_sudo_' "$log")" 0
}

# A machine that never enrolled must not fail the bootstrap.
@test "a home without handles reports one and adds nothing" {
    new_home none
    run --separate-stderr run_loader
    assert_success
    assert_stderr --partial 'no ~/.ssh/id_smortress_sudo'
    # The one line is ssh-add -L: the agent is asked, and nothing is added.
    assert_equal "$(wc -l <"$log" | tr -d '[:space:]')" 1
}

# No agent socket (launchd still starting) is the same silent no-op.
@test "no agent socket means no ssh-add" {
    home=$BATS_TEST_TMPDIR/noagent
    mkdir -p "$home/.ssh"
    handle id_smortress_sudo_1
    run run_loader
    assert_success
    assert_equal "$(wc -l <"$log" | tr -d '[:space:]')" 0
}

# Editor backups and temp files share the prefix; the loader must not hand one
# to the agent, because the pin check will not recognize it either.
@test "a stray file is not added and reports no handle" {
    new_home stray
    handle id_smortress_sudo_1~
    run --separate-stderr run_loader
    assert_success
    assert_equal "$(grep -c 'id_smortress_sudo_1~' "$log")" 0
    assert_stderr --partial 'no ~/.ssh/id_smortress_sudo'
}

# The pre-suffixed single name stays valid: a host enrolled before the per-key
# naming must keep working.
@test "the single pre-suffixed handle is added" {
    new_home legacy
    handle id_smortress_sudo
    run run_loader
    assert_success
    run cat "$log"
    assert_output --partial 'id_smortress_sudo'
}

# The Linux laptops run the same agent from a systemd user unit on the same
# socket, and Apple's FIDO provider does not exist there: OpenSSH links
# libfido2 directly, so the variable must not be set.
@test "handles are added on Linux without the Apple FIDO provider" {
    new_home linux
    handle id_smortress_sudo_1
    handle id_smortress_sudo_2
    printf '%s\n' Linux >"$os_file"
    run run_loader
    assert_success
    assert_equal "$(grep -c 'id_smortress_sudo_' "$log")" 2
    run grep -q 'provider=/usr/lib/ssh-keychain.dylib' "$log"
    assert_failure
}

# The same home and socket with the platform as the only difference: macOS needs
# the FIDO provider that OpenSSH on Linux finds on its own.
@test "the macOS provider is set on macOS" {
    new_home macos
    handle id_smortress_sudo_1
    handle id_smortress_sudo_2
    run run_loader
    assert_success
    run cat "$log"
    assert_output --partial 'provider=/usr/lib/ssh-keychain.dylib'
}

# No agent is the condition that matters, not the platform: a host whose unit
# has not started yet is a no-op rather than a failure.
@test "no agent socket is a no-op on another platform too" {
    printf '%s\n' FreeBSD >"$os_file"
    home=$BATS_TEST_TMPDIR/noagent2
    mkdir -p "$home/.ssh"
    handle id_smortress_sudo_1
    run run_loader
    assert_success
    assert_equal "$(grep -c 'id_smortress_sudo_' "$log")" 0
}
