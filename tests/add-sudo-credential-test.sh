#!/usr/bin/env bash
# The sudo credential loader: every handle goes in, a .pub never does, and a
# missing agent or missing handle is a log line rather than a failure.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

command -v python3 >/dev/null 2>&1 || skip_all "python3 is not installed to make an agent socket"

loader=$root/scripts/add-sudo-credential.sh
bin=$tmp/bin
log=$tmp/ssh-add.log
mkdir -p "$bin"

# Both agents bind the same socket, so the test is what decides the platform.
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

new_home() {  # new_home <name>: a HOME with a bound agent socket
    local home=$tmp/$1
    mkdir -p "$home/.local/state/ssh" "$home/.ssh"
    python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' \
        "$home/.local/state/ssh/agent.sock"
    printf '%s' "$home"
}
handle() {  # handle <home> <file>: a private handle and its public half
    : >"$1/.ssh/$2"
    # Distinct blobs: two handles are different credentials, and the loader
    # compares the key material to decide what is already in the agent.
    printf 'sk-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5%s %s\n' "$2" "$2" >"$1/.ssh/$2.pub"
}
run_loader() {  # run_loader <home> [file of loaded keys]
    : >"$log"
    env -i HOME="$1" PATH="$bin:/usr/bin:/bin" SSH_TEST_OS="$tmp/os" \
        SSH_ADD_LOG="$log" SSH_ADD_LOADED="${2:-}" sh "$loader"
}
on_os() { printf '%s\n' "$1" >"$tmp/os"; }
on_os Darwin

# One credential per YubiKey, as enrollment mints them: a tap on the spare has to
# work too, and the agent only offers what was added.
h=$(new_home three)
handle "$h" id_smortress_sudo_1
handle "$h" id_smortress_sudo_2
handle "$h" id_smortress_sudo_3
assert "the loader exits 0" run_loader "$h"
expect "every handle is added" 3 "$(grep -c 'id_smortress_sudo_[123] ' "$log")"
assert_not "no public half is added" grep -q '\.pub' "$log"

# A handle already in the agent must not be added again, but the other two are
# the whole point of the per-key naming: a spare key's tap has to work.
printf '%s\n' "$(cat "$h/.ssh/id_smortress_sudo_1.pub")" >"$tmp/loaded"
assert "the loader exits 0 with one handle already loaded" run_loader "$h" "$tmp/loaded"
expect "only the missing handles are added" 2 "$(grep -c 'id_smortress_sudo_' "$log")"
assert_not "the loaded handle is not re-added" grep -q 'id_smortress_sudo_1 ' "$log"

# All three loaded is the steady state, and a second bootstrap must be silent.
cat "$h"/.ssh/id_smortress_sudo_*.pub >"$tmp/loaded"
assert "the loader exits 0 with every handle loaded" run_loader "$h" "$tmp/loaded"
expect "nothing is added when every handle is loaded" 0 "$(grep -c 'id_smortress_sudo_' "$log")"

# A machine that never enrolled must not fail the bootstrap.
h=$(new_home none)
assert "the loader exits 0 without handles" run_loader "$h"
contains "the missing handle is reported" 'no ~/.ssh/id_smortress_sudo' "$out"
expect "nothing is added" 1 "$(wc -l <"$log")"

# No agent socket (launchd still starting) is the same silent no-op.
h=$tmp/noagent
mkdir -p "$h/.ssh"
handle "$h" id_smortress_sudo_1
assert "the loader exits 0 without an agent" run_loader "$h"
expect "no socket means no ssh-add" 0 "$(wc -l <"$log")"

# Editor backups and temp files share the prefix; the loader must not hand one
# to the agent, because the pin check will not recognize it either.
h=$(new_home stray)
handle "$h" id_smortress_sudo_1~
assert "the loader exits 0 with only a stray file" run_loader "$h"
expect "no stray file is added" 0 "$(grep -c 'id_smortress_sudo_1~' "$log")"
contains "a stray-only home reports no handle" 'no ~/.ssh/id_smortress_sudo' "$out"

# The pre-suffixed single name stays valid: a host enrolled before the per-key
# naming must keep working.
h=$(new_home legacy)
handle "$h" id_smortress_sudo
assert "the loader exits 0 on a single handle" run_loader "$h"
contains "the single handle is added" 'id_smortress_sudo' "$(cat "$log")"

# The Linux laptops run the same agent from a systemd user unit on the same
# socket, and Apple's FIDO provider does not exist there: OpenSSH links
# libfido2 directly, so the variable must not be set.
on_os Linux
h=$(new_home linux)
handle "$h" id_smortress_sudo_1
handle "$h" id_smortress_sudo_2
assert "the loader exits 0 on Linux" run_loader "$h"
expect "handles are added on Linux too" 2 "$(grep -c 'id_smortress_sudo_' "$log")"
assert_not "no Apple FIDO provider on Linux" grep -q 'provider=/usr/lib/ssh-keychain.dylib' "$log"
contains "the macOS provider is set on macOS" 'provider=/usr/lib/ssh-keychain.dylib' \
    "$(on_os Darwin; run_loader "$h"; cat "$log")"

# No agent is the condition that matters, not the platform: a host whose unit
# has not started yet is a no-op rather than a failure.
on_os FreeBSD
h=$tmp/noagent2
mkdir -p "$h/.ssh"
handle "$h" id_smortress_sudo_1
assert "the loader exits 0 without an agent on another platform" run_loader "$h"
expect "no socket, no adds" 0 "$(grep -c 'id_smortress_sudo_' "$log")"

finish
