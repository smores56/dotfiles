#!/usr/bin/env bats
# The sudo-pin check: a handle smortress does not pin, and a pin this machine
# cannot answer, are both drift, because either one turns a spare key's tap into
# a password prompt or leaves a retired key authorized for root.
load helpers

setup() {
    checker=$dotfiles_root/scripts/check-sudo-pins.sh
    bin=$BATS_TEST_TMPDIR/bin
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
    # The platform decides whether Apple's FIDO middleware is needed.
    cat >"$bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "${SSH_TEST_OS:-Linux}"
EOF
    chmod 755 "$bin/ssh-add" "$bin/uname"
}

new_home() {  # new_home <name>: a HOME with an empty ~/.ssh
    home=$BATS_TEST_TMPDIR/$1
    mkdir -p "$home/.ssh"
    printf '%s' "$home"
}

bind_agent() {  # bind_agent <home>: the loader's socket, bound by python3
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
    local file=$1 n
    shift
    : >"$file"
    for n in "$@"; do
        printf 'sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5AAAA%s smores-sudo-key%s\n' \
            "$n" "$n" >>"$file"
    done
    printf '%s' "$file"
}

# route <home> <pins file|empty> [ENV=VAL...]: the real bootstrap path, with the
# caller's environment swapped out so no ambient knob can decide a case.
route() {
    local home=$1 pins_file=$2
    shift 2
    env -i HOME="$home" PATH=/usr/bin:/bin SUDO_PINS_FILE="$pins_file" \
        SSH_TEST_OS=Linux "$@" sh "$checker"
}

# agent_home: three handles on disk and a socket the fake agent answers, into
# $agent. Only these cases need python3, so only they skip without it.
agent_home() {
    command -v python3 >/dev/null 2>&1 \
        || skip "python3 is not installed to bind an agent socket"
    agent=$(new_home agent)
    handle "$agent" 1
    handle "$agent" 2
    handle "$agent" 3
    bind_agent "$agent"
}

@test "a matching set exits 0 and stays silent" {
    home=$(new_home match)
    handle "$home" 1
    handle "$home" 2
    handle "$home" 3
    p=$(pins "$BATS_TEST_TMPDIR/match.pins" 1 2 3)
    run --separate-stderr route "$home" "$p"
    assert_success
    assert_equal "$status" 0
    assert_silent
}

# A fourth YubiKey enrolled on the machine but never added to the image: its tap
# authenticates nothing, and the loader happily hands it to the agent.
@test "an unpinned handle fails the check" {
    home=$(new_home extra)
    handle "$home" 1
    handle "$home" 2
    handle "$home" 3
    handle "$home" 4
    p=$(pins "$BATS_TEST_TMPDIR/extra.pins" 1 2 3)
    run --separate-stderr route "$home" "$p"
    assert_failure
    assert_equal "$status" 1
    assert_stderr --partial 'smores-sudo-key4'
    assert_stderr --partial 'not pinned'
}

# A pin left behind after a key is retired stays authorized for root on
# smortress, and this machine can no longer answer for it.
@test "a pin with no handle fails the check" {
    home=$(new_home short)
    handle "$home" 1
    handle "$home" 2
    p=$(pins "$BATS_TEST_TMPDIR/short.pins" 1 2 3)
    run --separate-stderr route "$home" "$p"
    assert_failure
    assert_stderr --partial 'smores-sudo-key3'
    assert_stderr --partial 'no handle'
}

# The work Mac has no homelab-platform checkout, so the pins are unknowable
# there and the bootstrap must not fail.
@test "a machine without the pinned file exits 0" {
    home=$(new_home mac)
    handle "$home" 1
    run --separate-stderr route "$home" "$BATS_TEST_TMPDIR/absent.pins"
    assert_success
    assert_stderr --partial 'not checking'
}

# A machine that never enrolled is the loader's no-op too: the password is the
# way in, and a spare key's tap has nothing to do with it.
@test "a machine with no handles exits 0" {
    home=$(new_home none)
    p=$(pins "$BATS_TEST_TMPDIR/none.pins" 1 2 3)
    run --separate-stderr route "$home" "$p"
    assert_success
    assert_stderr --partial 'nothing to compare'
}

# An authority that pins nothing is broken, not clean, and that holds on the
# first machine to bootstrap as much as on an enrolled one.
@test "an empty pinned file fails" {
    home=$(new_home blank)
    : >"$BATS_TEST_TMPDIR/blank.pins"
    run --separate-stderr route "$home" "$BATS_TEST_TMPDIR/blank.pins"
    assert_failure
    assert_stderr --partial 'holds no keys'
    handle "$home" 1
    run --separate-stderr route "$home" "$BATS_TEST_TMPDIR/blank.pins"
    assert_failure
    assert_equal "$status" 1
}

# Annotations and re-runs of the enrollment command leave blanks, comments and
# duplicate lines in the file; only the key material decides.
@test "comments, blanks and duplicate pins are ignored" {
    home=$(new_home dirty)
    handle "$home" 1
    handle "$home" 2
    body=$(pins "$BATS_TEST_TMPDIR/dirty.body" 1 2)
    p=$BATS_TEST_TMPDIR/dirty.pins
    {
        printf '# smortress sudo credentials\n\n'
        cat "$body" "$body"
    } >"$p"
    run --separate-stderr route "$home" "$p"
    assert_success
    assert_silent
}

# Enrollment writes the .pub next to the handle; when it is gone the check says
# so rather than quietly passing a handle it could not compare.
@test "a handle without its public half fails the check" {
    home=$(new_home nopub)
    handle "$home" 1
    rm -f "$home/.ssh/id_smortress_sudo_1.pub"
    p=$(pins "$BATS_TEST_TMPDIR/nopub.pins" 1)
    run --separate-stderr route "$home" "$p"
    assert_failure
    assert_stderr --partial 'id_smortress_sudo_1'
    assert_stderr --partial 'has no .pub'
}

# An enrollment that wrote an empty .pub is the same blind spot, and set -e
# must not turn it into a bare exit with no line saying which handle it was.
@test "an empty public half fails the check" {
    home=$(new_home empty)
    handle "$home" 1
    : >"$home/.ssh/id_smortress_sudo_1.pub"
    p=$(pins "$BATS_TEST_TMPDIR/empty.pins" 1)
    run --separate-stderr route "$home" "$p"
    assert_failure
    assert_stderr --partial 'id_smortress_sudo_1'
    assert_stderr --partial 'holds no key'
}

# Editor backups and temp files share the handle prefix; they are not enrolled
# keys, and the loader skips them too, so they must not fail the bootstrap.
@test "stray files beside the handles are ignored" {
    home=$(new_home stray)
    handle "$home" 1
    : >"$home/.ssh/id_smortress_sudo_1~"
    : >"$home/.ssh/id_smortress_sudo_1.pub.swo"
    p=$(pins "$BATS_TEST_TMPDIR/stray.pins" 1)
    run --separate-stderr route "$home" "$p"
    assert_success
    assert_silent
}

# The agent is what sudo actually signs with: a pinned key it does not hold is
# the silent password fallback, and a key it holds that the image does not pin
# is a tap that authenticates nothing.
@test "a pinned key the agent does not hold fails the check" {
    agent_home
    p=$(pins "$BATS_TEST_TMPDIR/agent.pins" 1 2 3)
    cat "$agent/.ssh/id_smortress_sudo_1.pub" >"$BATS_TEST_TMPDIR/loaded-one"
    run --separate-stderr route "$agent" "$p" \
        PATH="$bin:/usr/bin:/bin" SSH_ADD_KEYS="$BATS_TEST_TMPDIR/loaded-one"
    assert_failure
    assert_stderr --partial 'smores-sudo-key2'
    assert_stderr --partial 'does not hold'
}

@test "a fully served set exits 0" {
    agent_home
    p=$(pins "$BATS_TEST_TMPDIR/agent.pins" 1 2 3)
    cat "$agent"/.ssh/id_smortress_sudo_*.pub >"$BATS_TEST_TMPDIR/loaded-all"
    run --separate-stderr route "$agent" "$p" \
        PATH="$bin:/usr/bin:/bin" SSH_ADD_KEYS="$BATS_TEST_TMPDIR/loaded-all"
    assert_success
    assert_silent
}

@test "an unpinned key the agent holds fails the check" {
    agent_home
    p=$(pins "$BATS_TEST_TMPDIR/agent.pins" 1 2 3)
    cat "$agent"/.ssh/id_smortress_sudo_*.pub >"$BATS_TEST_TMPDIR/loaded-all"
    nine=$(new_home nine)
    handle "$nine" 9
    {
        cat "$BATS_TEST_TMPDIR/loaded-all"
        cat "$nine/.ssh/id_smortress_sudo_9.pub"
    } >"$BATS_TEST_TMPDIR/loaded-extra"
    run --separate-stderr route "$agent" "$p" \
        PATH="$bin:/usr/bin:/bin" SSH_ADD_KEYS="$BATS_TEST_TMPDIR/loaded-extra"
    assert_failure
    assert_stderr --partial 'smores-sudo-key9'
}

# An empty agent is the no-YubiKey case the loader already logs: one line, not
# a second failure, and the password is the way in.
@test "an empty agent stays quiet" {
    agent_home
    p=$(pins "$BATS_TEST_TMPDIR/agent.pins" 1 2 3)
    run --separate-stderr route "$agent" "$p" PATH="$bin:/usr/bin:/bin"
    assert_success
    assert_equal "$status" 0
    assert_stderr --partial 'holds no keys'
}

# A socket that no agent answers is the loader's logged failure too.
@test "a dead agent stays quiet" {
    agent_home
    p=$(pins "$BATS_TEST_TMPDIR/agent.pins" 1 2 3)
    run --separate-stderr route "$agent" "$p" \
        PATH="$bin:/usr/bin:/bin" SSH_ADD_FAIL=2
    assert_success
    assert_stderr --partial 'did not answer'
}

# Apple's OpenSSH needs its own FIDO middleware for the sk handles.
@test "a served set exits 0 on Darwin" {
    agent_home
    p=$(pins "$BATS_TEST_TMPDIR/agent.pins" 1 2 3)
    cat "$agent"/.ssh/id_smortress_sudo_*.pub >"$BATS_TEST_TMPDIR/loaded-all"
    log=$BATS_TEST_TMPDIR/agent.log
    run --separate-stderr route "$agent" "$p" PATH="$bin:/usr/bin:/bin" \
        SSH_ADD_KEYS="$BATS_TEST_TMPDIR/loaded-all" SSH_TEST_OS=Darwin SSH_ADD_LOG="$log"
    assert_success
    run --separate-stderr cat "$log"
    assert_success
    assert_output --partial '/usr/lib/ssh-keychain.dylib'
}

# The checkout is found through the same knob the SOPS audit uses, so a moved
# root breaks one convention, not a second hardcoded one.
@test "HOMELAB_REPO locates the pinned file" {
    home=$(new_home route)
    handle "$home" 1
    repo=$BATS_TEST_TMPDIR/repo
    mkdir -p "$repo/image/rootfs/etc/ssh"
    pins "$repo/image/rootfs/etc/ssh/sudo_authorized_keys" 1 >/dev/null
    run --separate-stderr route "$home" '' HOMELAB_REPO="$repo"
    assert_success
    assert_silent
}
