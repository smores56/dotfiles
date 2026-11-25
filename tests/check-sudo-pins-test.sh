#!/usr/bin/env bash
# The sudo-pin check: a handle smortress does not pin, and a pin this machine
# cannot answer, are both drift, because either one turns a spare key's tap into
# a password prompt or leaves a retired key authorized for root.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

command -v python3 >/dev/null 2>&1 || skip_all "python3 is not installed to bind an agent socket"

checker=$root/scripts/check-sudo-pins.sh
bin=$tmp/bin
mkdir -p "$bin"
# The agent is what signs: -L prints whatever the case staged, "no identities"
# is the real empty-agent shape, and refusing to see the socket is itself a
# failure the test catches.
cat >"$bin/ssh-add" <<'EOF'
#!/bin/sh
[ -S "$SSH_AUTH_SOCK" ] || exit 3
[ "${1:-}" = -L ] || exit 1
[ -n "${SSH_ADD_LOG:-}" ] && printf 'provider=%s\n' "${SSH_SK_PROVIDER:-none}" >>"$SSH_ADD_LOG"
[ "${SSH_ADD_FAIL:-0}" -ne 0 ] && exit "$SSH_ADD_FAIL"
[ -n "${SSH_ADD_KEYS:-}" ] || { printf 'The agent has no identities.\n' >&2; exit 1; }
cat "$SSH_ADD_KEYS"
EOF
cat >"$bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "${SSH_TEST_OS:-Linux}"
EOF
chmod 755 "$bin/ssh-add" "$bin/uname"

new_home() {  # new_home <name>
    local home=$tmp/$1
    mkdir -p "$home/.ssh"
    printf '%s' "$home"
}
bind_agent() {  # bind_agent <home>
    mkdir -p "$1/.local/state/ssh"
    python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' \
        "$1/.local/state/ssh/agent.sock"
}
# Enrollment mints one resident handle per YubiKey. The key material is what a
# pin compares; the comment is only a label, in the real sk format.
handle() {  # handle <home> <n>
    : >"$1/.ssh/id_smortress_sudo_$2"
    printf 'sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5AAAA%s smores-sudo-key%s\n' \
        "$2" "$2" >"$1/.ssh/id_smortress_sudo_$2.pub"
}
pins() {  # pins <file> <n>...: the server image's authorized set
    local file=$1
    shift
    : >"$file"
    for n in "$@"; do
        printf 'sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5AAAA%s smores-sudo-key%s\n' \
            "$n" "$n" >>"$file"
    done
    printf '%s' "$file"
}
route() {  # route <home> <pins file|empty>: the real bootstrap path
    env -i HOME="$1" PATH="${CHECK_PATH:+$CHECK_PATH:}/usr/bin:/bin" \
        HOMELAB_REPO="${HOMELAB_REPO:-}" SUDO_PINS_FILE="${2:-}" \
        SSH_ADD_KEYS="${SSH_ADD_KEYS:-}" SSH_ADD_FAIL="${SSH_ADD_FAIL:-0}" \
        SSH_ADD_LOG="${SSH_ADD_LOG:-}" SSH_TEST_OS="${SSH_TEST_OS:-Linux}" \
        sh "$checker"
}
# Cross-checked through message assertions: a checker that aborts must not pass
# for a checker that reports drift.
status_of() {  # status_of <cmd...>
    "$@" >/dev/null 2>&1
    printf '%s' "$?"
}

h=$(new_home match)
handle "$h" 1
handle "$h" 2
handle "$h" 3
p=$(pins "$tmp/match.pins" 1 2 3)
assert "a matching set exits 0" route "$h" "$p"
expect "a matching set is silent" '' "$out"
expect "a matching set exits with 0" 0 "$(status_of route "$h" "$p")"

# A fourth YubiKey enrolled on the machine but never added to the image: its tap
# authenticates nothing, and the loader happily hands it to the agent.
h=$(new_home extra)
handle "$h" 1
handle "$h" 2
handle "$h" 3
handle "$h" 4
p=$(pins "$tmp/extra.pins" 1 2 3)
assert_not "an unpinned handle fails the check" route "$h" "$p"
contains "the unpinned handle is labelled" 'smores-sudo-key4' "$out"
contains "the unpinned handle is named as unpinned" 'not pinned' "$out"
expect "drift exits with 1" 1 "$(status_of route "$h" "$p")"

# A pin left behind after a key is retired stays authorized for root on
# smortress, and this machine can no longer answer for it.
h=$(new_home short)
handle "$h" 1
handle "$h" 2
p=$(pins "$tmp/short.pins" 1 2 3)
assert_not "a pin with no handle fails the check" route "$h" "$p"
contains "the missing handle is labelled" 'smores-sudo-key3' "$out"
contains "the missing handle is named" 'no handle' "$out"

# The work Mac has no homelab-platform checkout, so the pins are unknowable
# there and the bootstrap must not fail.
h=$(new_home mac)
handle "$h" 1
assert "a machine without the pinned file exits 0" route "$h" "$tmp/absent.pins"
contains "the missing pinned file is reported" 'not checking' "$out"

# A machine that never enrolled is the loader's no-op too: the password is the
# way in, and a spare key's tap has nothing to do with it.
h=$(new_home none)
p=$(pins "$tmp/none.pins" 1 2 3)
assert "a machine with no handles exits 0" route "$h" "$p"
contains "the missing handles are reported" 'nothing to compare' "$out"

# An authority that pins nothing is broken, not clean, and that holds on the
# first machine to bootstrap as much as on an enrolled one.
h=$(new_home blank)
: >"$tmp/blank.pins"
assert_not "an empty pinned file fails without handles" route "$h" "$tmp/blank.pins"
contains "the empty pinned file is reported" 'holds no keys' "$out"
handle "$h" 1
assert_not "an empty pinned file fails with handles" route "$h" "$tmp/blank.pins"
expect "an empty pinned file exits with 1" 1 "$(status_of route "$h" "$tmp/blank.pins")"

# Annotations and re-runs of the enrollment command leave blanks, comments and
# duplicate lines in the file; only the key material decides.
h=$(new_home dirty)
handle "$h" 1
handle "$h" 2
body=$(pins "$tmp/dirty.body" 1 2)
p=$tmp/dirty.pins
{
    printf '# smortress sudo credentials\n\n'
    cat "$body" "$body"
} >"$p"
assert "comments, blanks and duplicate pins are ignored" route "$h" "$p"
expect "a dirty pinned file is silent" '' "$out"

# Enrollment writes the .pub next to the handle; when it is gone the check says
# so rather than quietly passing a handle it could not compare.
h=$(new_home nopub)
handle "$h" 1
rm -f "$h/.ssh/id_smortress_sudo_1.pub"
p=$(pins "$tmp/nopub.pins" 1)
assert_not "a handle without its public half fails the check" route "$h" "$p"
contains "the uncomparable handle is named" 'id_smortress_sudo_1' "$out"

# An enrollment that wrote an empty .pub is the same blind spot, and set -e
# must not turn it into a bare exit with no line saying which handle it was.
h=$(new_home empty)
handle "$h" 1
: >"$h/.ssh/id_smortress_sudo_1.pub"
p=$(pins "$tmp/empty.pins" 1)
assert_not "an empty public half fails the check" route "$h" "$p"
contains "the empty public half is named" 'id_smortress_sudo_1' "$out"

# Editor backups and temp files share the handle prefix; they are not enrolled
# keys, and the loader skips them too, so they must not fail the bootstrap.
h=$(new_home stray)
handle "$h" 1
: >"$h/.ssh/id_smortress_sudo_1~"
: >"$h/.ssh/id_smortress_sudo_1.pub.swo"
p=$(pins "$tmp/stray.pins" 1)
assert "stray files beside the handles are ignored" route "$h" "$p"
expect "stray files are silent" '' "$out"

# The agent is what sudo actually signs with: a pinned key it does not hold is
# the silent password fallback, and a key it holds that the image does not pin
# is a tap that authenticates nothing.
h=$(new_home agent)
handle "$h" 1
handle "$h" 2
handle "$h" 3
bind_agent "$h"
p=$(pins "$tmp/agent.pins" 1 2 3)
cat "$h/.ssh/id_smortress_sudo_1.pub" >"$tmp/loaded-one"
CHECK_PATH=$bin SSH_ADD_KEYS=$tmp/loaded-one assert_not \
    "a pinned key the agent does not hold fails the check" route "$h" "$p"
contains "the unheld pin is labelled" 'smores-sudo-key2' "$out"
contains "the unheld pin is named" 'does not hold' "$out"
cat "$h"/.ssh/id_smortress_sudo_*.pub >"$tmp/loaded-all"
CHECK_PATH=$bin SSH_ADD_KEYS=$tmp/loaded-all assert "a fully served set exits 0" route "$h" "$p"
expect "a fully served set is silent" '' "$out"
h9=$(new_home nine)
handle "$h9" 9
{ cat "$tmp/loaded-all"; cat "$h9/.ssh/id_smortress_sudo_9.pub"; } >"$tmp/loaded-extra"
CHECK_PATH=$bin SSH_ADD_KEYS=$tmp/loaded-extra assert_not \
    "an unpinned key the agent holds fails the check" route "$h" "$p"
contains "the unheld extra is labelled" 'smores-sudo-key9' "$out"
# An empty agent is the no-YubiKey case the loader already logs: one line, not
# a second failure, and the password is the way in.
CHECK_PATH=$bin assert "an empty agent stays quiet" route "$h" "$p"
contains "the empty agent is reported" 'holds no keys' "$out"
expect "an empty agent exits with 0" 0 "$(CHECK_PATH=$bin status_of route "$h" "$p")"
# A socket that no agent answers is the loader's logged failure too.
CHECK_PATH=$bin SSH_ADD_FAIL=2 assert "a dead agent stays quiet" route "$h" "$p"
contains "the dead agent is reported" 'did not answer' "$out"
# Apple's OpenSSH needs its own FIDO middleware for the sk handles.
rm -f "$tmp/agent.log"
CHECK_PATH=$bin SSH_ADD_KEYS=$tmp/loaded-all SSH_TEST_OS=Darwin \
    SSH_ADD_LOG=$tmp/agent.log assert "a served set exits 0 on Darwin" route "$h" "$p"
contains "Apple's security-key provider reaches the agent" \
    '/usr/lib/ssh-keychain.dylib' "$(cat "$tmp/agent.log" 2>/dev/null)"

# The checkout is found through the same knob the SOPS audit uses, so a moved
# root breaks one convention, not a second hardcoded one.
h=$(new_home route)
handle "$h" 1
repo=$tmp/repo
mkdir -p "$repo/image/rootfs/etc/ssh"
pins "$repo/image/rootfs/etc/ssh/sudo_authorized_keys" 1 >/dev/null
HOMELAB_REPO=$repo SUDO_PINS_FILE='' assert "HOMELAB_REPO locates the pinned file" route "$h"
expect "the located set is silent" '' "$out"

finish
