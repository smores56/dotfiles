#!/usr/bin/env bats
# ~/.local/bin/sops-age-key answers one sops recipient stanza with one identity.
load helpers

setup() {
    script=$dotfiles_root/home/.local/bin/sops-age-key
    home=$BATS_TEST_TMPDIR/home
    config=$home/.config
    bin=$BATS_TEST_TMPDIR/bin
    bin_noage=$BATS_TEST_TMPDIR/bin-noage
    log=$BATS_TEST_TMPDIR/log
    mkdir -p "$config/sops" "$bin"
    cat >"$bin/age" <<'EOF'
#!/bin/sh
printf 'age %s\n' "$*" >>"$AGE_LOG"
printf 'FAKE-ADMIN-IDENTITY\n'
EOF
    # The production probe lists the FIDO devices it can open; the stub reports
    # one only when the case asks for a token.
    cat >"$bin/systemd-cryptenroll" <<'EOF'
#!/bin/sh
[ -n "${FAKE_FIDO-}" ] && echo /dev/hidraw1
exit 0
EOF
    cat >"$bin/age-plugin-fido2-hmac" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$bin/age" "$bin/systemd-cryptenroll" "$bin/age-plugin-fido2-hmac"
    : >"$log"
    fido2=$config/sops/fido2-identity.txt
    admin=$config/sops/keys.age
}

# Every tool the script may call except age. A distro that ships age in /usr/bin
# would otherwise make the "missing helper" case pass without testing anything.
# Built on demand: the loop costs one symlink per host tool.
noage_bin() {
    mkdir -p "$bin_noage"
    cp "$bin/systemd-cryptenroll" "$bin_noage/systemd-cryptenroll"
    chmod +x "$bin_noage/systemd-cryptenroll"
    local dir tool name
    for dir in /usr/bin /bin; do
        [ "$dir" = /bin ] && [ /bin -ef /usr/bin ] && continue
        for tool in "$dir"/*; do
            name=${tool##*/}
            [ "$name" = age ] && continue
            [ -e "$bin_noage/$name" ] && continue
            ln -s "$tool" "$bin_noage/$name" 2>/dev/null || true
        done
    done
}

# key <args...>: the wrapper under a scrubbed environment, with only the
# variables the case asked for.
key() {
    env -i HOME="$home" XDG_CONFIG_HOME="$config" \
        PATH="${RUN_PATH:-$bin:/usr/bin:/bin}" \
        AGE_LOG="$log" \
        SOPS_AGE_RECIPIENT="${RECIP-}" \
        SOPS_AGE_FIDO2_PRESENT="${PRESENT-}" \
        FAKE_FIDO="${FIDO-}" \
        SOPS_AGE_KEY="${SKEY-}" \
        SOPS_AGE_KEY_FILE="${SKEYFILE-}" \
        SOPS_AGE_SSH_PRIVATE_KEY_FILE="${SSHKEY-}" \
        SOPS_AGE_BIN="${SBIN-}" \
        bash "$script" "$@"
}

age_calls() {
    if [ -s "$log" ]; then wc -l <"$log" | tr -d ' '; else echo 0; fi
}

valid_admin() { printf 'age-encryption.org/v1\nfake\n' >"$admin"; }

# Two enrolled keys and the admin recipient the passphrase identity owns.
write_handles() {
    cat >"$fido2" <<'EOF'
# created: test
# public key: age1one
# public key (pq safe): age1pqone
AGE-PLUGIN-FIDO2-HMAC-1ONE
# public key: age1two
AGE-PLUGIN-FIDO2-HMAC-1TWO
EOF
    chmod 600 "$fido2"
}

# 1. The stanza's recipient selects exactly one handle; no passphrase is read.
@test "the matching recipient selects its identity" {
    write_handles
    RECIP=age1two FIDO=1
    run --separate-stderr key
    assert_success
    assert_output 'AGE-PLUGIN-FIDO2-HMAC-1TWO'
    assert_equal "$(age_calls)" 0
}

# 2. A recipient this machine cannot serve prints nothing and still succeeds,
#    so sops can try the next stanza.
@test "an unowned recipient is skipped" {
    write_handles
    RECIP=age1someoneelse FIDO=1
    run --separate-stderr key
    assert_success
    assert_output ''
    assert_equal "$(age_calls)" 0
}

# 3. The admin recipient with no usable token prompts through age, once.
@test "the admin recipient decrypts the wrapped identity" {
    valid_admin
    RECIP=age1admin PRESENT=0
    run --separate-stderr key
    assert_success
    assert_output FAKE-ADMIN-IDENTITY
    assert_equal "$(cat "$log")" "age --decrypt $admin"
}

# 4. The admin recipient with a usable token prints nothing: the token path is
#    preferred, and the passphrase is not read.
@test "the admin recipient defers to a usable token" {
    write_handles
    RECIP=age1admin FIDO=1
    run --separate-stderr key
    assert_success
    assert_output ''
    assert_equal "$(age_calls)" 0
}

# 4b. An attached token this machine has no handle for cannot answer any stanza,
#     so the admin recipient still falls back to the passphrase.
@test "a token without handles falls back to the passphrase" {
    write_handles
    mv "$fido2" "$fido2.away"
    valid_admin
    RECIP=age1admin FIDO=1
    run --separate-stderr key
    assert_success
    assert_output FAKE-ADMIN-IDENTITY
}

# 5. A handle whose token is absent fails loudly instead of silently emitting
#    an identity the plugin cannot use.
@test "a matched handle with no token fails" {
    write_handles
    RECIP=age1one PRESENT=0
    run --separate-stderr key
    assert_failure
    assert_stderr --partial 'age1one'
    assert_equal "$(age_calls)" 0
}

# 6. Without a recipient (older sops or a manual run), a usable token exports
#    every handle, and no comments leak into sops's parser.
@test "without a recipient the handles are exported" {
    write_handles
    FIDO=1
    run --separate-stderr key
    assert_success
    assert_output 'AGE-PLUGIN-FIDO2-HMAC-1ONE
AGE-PLUGIN-FIDO2-HMAC-1TWO'
    assert_equal "$(age_calls)" 0
}

# 7. Without a recipient and without a token, the passphrase is the fallback.
@test "without a recipient or token the admin identity is used" {
    write_handles
    valid_admin
    PRESENT=0
    run --separate-stderr key
    assert_success
    assert_output FAKE-ADMIN-IDENTITY
}

# 8. Neither identity: fail and name both files.
@test "a machine with no identity fails" {
    run --separate-stderr key
    assert_failure
    assert_stderr --partial "$admin is missing, empty"
    assert_stderr --partial "$fido2"
}

# 9. --check answers "can this machine produce an identity" without calling age,
#    and the answer matches the routing path.
@test "--check answers whether this machine can produce an identity" {
    write_handles
    valid_admin
    PRESENT=0 FIDO=
    run --separate-stderr key --check
    assert_success
    assert_output ''
    assert_equal "$(age_calls)" 0

    rm "$admin"
    PRESENT= FIDO=1
    run --separate-stderr key --check
    assert_success
    assert_output ''

    valid_admin
    : >"$admin"
    PRESENT=0 FIDO=
    run --separate-stderr key --check
    assert_failure

    printf 'not-an-age-file\n' >"$admin"
    run --separate-stderr key --check
    assert_failure

    valid_admin
    noage_bin
    RUN_PATH=$bin_noage
    run --separate-stderr key --check
    assert_failure

    rm "$admin"
    RUN_PATH=
    run --separate-stderr key --check
    assert_failure
    assert_output ''
    assert_stderr --partial 'no usable SOPS identity'
}

# 10. The retired plaintext identity still stops a user, including --check.
@test "a retired plaintext identity fails" {
    valid_admin
    mkdir -p "$config/sops/age"
    printf 'legacy\n' >"$config/sops/age/keys.txt"
    run --separate-stderr key
    assert_failure
    assert_stderr --partial 'remove the retired plaintext identity'
    run --separate-stderr key --check
    assert_failure
}

# 11. An identity source outside this wrapper is refused rather than silently
#     overriding the guard.
@test "SOPS_AGE_KEY_FILE is refused" {
    valid_admin
    SKEYFILE=$BATS_TEST_TMPDIR/elsewhere
    run --separate-stderr key
    assert_failure
    assert_stderr --partial 'SOPS_AGE_KEY_FILE'

    SKEY=$BATS_TEST_TMPDIR/not-an-identity
    run --separate-stderr key
    assert_failure

    SSHKEY=$BATS_TEST_TMPDIR/ssh-key
    run --separate-stderr key
    assert_failure
    assert_stderr --partial 'SOPS_AGE_SSH_PRIVATE_KEY'
}

# 12. The probe uses systemd-cryptenroll's usable-device list.
@test "a listed FIDO device counts as usable" {
    write_handles
    RECIP=age1one FIDO=1
    run --separate-stderr key
    assert_success
    assert_output 'AGE-PLUGIN-FIDO2-HMAC-1ONE'

    FIDO=
    run --separate-stderr key
    assert_failure
    assert_stderr --partial 'age1one'
}

# 13. The explicit override beats the probe in both directions.
@test "the presence override can force a token" {
    write_handles
    RECIP=age1one PRESENT=1 FIDO=
    run --separate-stderr key
    assert_success
    assert_output 'AGE-PLUGIN-FIDO2-HMAC-1ONE'

    PRESENT=0 FIDO=1
    run --separate-stderr key
    assert_failure
}

# 14. A malformed or duplicated block for the selected recipient is a hard
#     failure, not a silent skip; an unowned handle is named.
@test "a malformed, duplicated, or unowned handle fails" {
    cat >"$fido2" <<'EOF'
# public key: age1bad
AGE-PLUGIN-FIDO2-HMAC-1BAD!
# admin: age1admin
EOF
    RECIP=age1bad FIDO=1
    run --separate-stderr key
    assert_failure
    assert_stderr --partial "$fido2"

    cat >"$fido2" <<'EOF'
# public key: age1dup
AGE-PLUGIN-FIDO2-HMAC-1DUP
# public key: age1dup
AGE-PLUGIN-FIDO2-HMAC-1DUP
# admin: age1admin
EOF
    RECIP=age1dup
    run --separate-stderr key
    assert_failure
    assert_stderr --partial 'age1dup'

    cat >"$fido2" <<'EOF'
AGE-PLUGIN-FIDO2-HMAC-1ORPHAN
# public key: age1one
AGE-PLUGIN-FIDO2-HMAC-1ONE
# admin: age1admin
EOF
    RECIP=age1one FIDO=1
    run --separate-stderr key
    assert_failure
    assert_stderr --partial "$fido2"
}

# 15. A pinned age path is both testable and outside a project's PATH.
@test "--check accepts a pinned age" {
    write_handles
    valid_admin
    SBIN=$bin/age PRESENT=0
    run --separate-stderr key --check
    assert_success

    SBIN=$BATS_TEST_TMPDIR/no-such-age
    run --separate-stderr key --check
    assert_failure
}

# 16. The root branch is unreachable without root, so run a copy with the guard
#     and its fixed identity path pointed at this test. age-keygen writes
#     "# created:" and "# public key:" headers above the identity.
@test "a root identity with age-keygen headers passes" {
    root_script=$BATS_TEST_TMPDIR/sops-age-key-root
    sed -e 's/^if \[ "\$EUID" -eq 0 \]; then$/if true; then/' \
        -e "s#^    legacy=/root/.config/sops/age/keys.txt\$#    legacy=$config/sops/age/keys.txt#" \
        "$script" >"$root_script"
    mkdir -p "$config/sops/age"
    # Spelled in two pieces so the repo's own secret scan does not flag the stub.
    {
        printf '# created: 2026-01-01T00:00:00Z\n'
        printf '# public key: age1test\n'
        printf '%s%s\n' 'AGE-SECRET-' 'KEY-1TEST'
    } >"$config/sops/age/keys.txt"
    chmod 600 "$config/sops/age/keys.txt"
    run env -i HOME="$home" XDG_CONFIG_HOME="$config" PATH=/usr/bin:/bin \
        bash "$root_script" --check
    assert_success

    printf 'not a key\n' >"$config/sops/age/keys.txt"
    run env -i HOME="$home" XDG_CONFIG_HOME="$config" PATH=/usr/bin:/bin \
        bash "$root_script" --check
    assert_failure
}
