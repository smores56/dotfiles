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

# The loader is macOS-only by design; the test is what decides the platform.
cat >"$bin/uname" <<'EOF'
#!/bin/sh
printf 'Darwin\n'
EOF
# ssh-add records its argv, and `-l` reports whatever the case staged.
cat >"$bin/ssh-add" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$SSH_ADD_LOG"
[ "${1:-}" = -l ] && [ -n "$SSH_ADD_LIST" ] && printf '%s\n' "$SSH_ADD_LIST"
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
    printf 'sk-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 %s\n' "$2" >"$1/.ssh/$2.pub"
}
run_loader() {  # run_loader <home> [ssh-add -l output]
    : >"$log"
    env -i HOME="$1" PATH="$bin:/usr/bin:/bin" \
        SSH_ADD_LOG="$log" SSH_ADD_LIST="${2:-}" sh "$loader"
}

# One credential per YubiKey, as enrollment mints them: a tap on the spare has to
# work too, and the agent only offers what was added.
h=$(new_home three)
handle "$h" id_smortress_sudo_1
handle "$h" id_smortress_sudo_2
handle "$h" id_smortress_sudo_3
assert "the loader exits 0" run_loader "$h"
expect "every handle is added" 3 "$(grep -c 'id_smortress_sudo_[123]$' "$log")"
assert_not "no public half is added" grep -q '\.pub' "$log"

# A resident handle is already in the agent after the first bootstrap; asking
# for a second one is friction, not a fix.
assert "the loader exits 0 with a loaded handle" \
    run_loader "$h" '256 SHA256:aaaa smores-sudo-key1 (ED25519-SK)'
expect "a loaded handle stops the adds" 1 "$(wc -l <"$log")"

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

# The pre-suffixed single name stays valid: a host enrolled before the per-key
# naming must keep working.
h=$(new_home legacy)
handle "$h" id_smortress_sudo
assert "the loader exits 0 on a single handle" run_loader "$h"
contains "the single handle is added" 'id_smortress_sudo' "$(cat "$log")"

finish
