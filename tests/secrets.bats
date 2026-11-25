#!/usr/bin/env bats
# scripts/secrets.sh against a fake sops: one decrypt into the Maki provider
# keys, the machine's GitHub token, and the smortress ssh key.
load helpers

setup() {
    home=$BATS_TEST_TMPDIR/home
    bin=$BATS_TEST_TMPDIR/bin
    cipher=$BATS_TEST_TMPDIR/secrets.yaml
    log=$BATS_TEST_TMPDIR/log
    mkdir -p "$home/.config/sops" "$bin"
    : >"$log"
    : >"$home/.config/sops/keys.age"
    printf 'encrypted\n' >"$cipher"

    cat >"$bin/sops" <<'EOF'
#!/bin/sh
printf 'sops\n' >>"$SECRETS_LOG"
printf 'NEURALWATT_API_KEY=%s\n' "$FAKE_NEURALWATT"
printf 'TINYFISH_API_KEY=%s\n' "$FAKE_TINYFISH"
[ -n "$FAKE_PAT" ] && printf 'GITHUB_PERSONAL_PAT=%s\n' "$FAKE_PAT"
[ -n "$FAKE_WORK_PAT" ] && printf 'GITHUB_WORK_PAT=%s\n' "$FAKE_WORK_PAT"
[ -n "$FAKE_SMORTRESS_SSH_KEY" ] && printf 'SMORTRESS_SSH_KEY=%s\n' "$FAKE_SMORTRESS_SSH_KEY"
exit 0
EOF
    # The token is exported by the shell env, never handed to gh: any gh call is a
    # failure.
    cat >"$bin/gh" <<'EOF'
#!/bin/sh
printf 'gh %s\n' "$*" >>"$SECRETS_LOG"
EOF
    # Stands in for `mise exec`, which exports the saved set only when it is
    # non-empty.
    cat >"$bin/mise" <<'EOF'
#!/bin/sh
printf 'mise %s\n' "$*" >>"$SECRETS_LOG"
[ -z "${FAKE_MISE_FAIL-}" ] || exit 1
[ "$1 $2" = "exec --" ] || exit 2
shift 2
[ -z "${FAKE_MISE_ENV-}" ] || { MISE_ENV=$FAKE_MISE_ENV; export MISE_ENV; }
exec "$@"
EOF
    chmod +x "$bin/sops" "$bin/gh" "$bin/mise"

    # What a test overrides before calling secrets(); an empty fake_* is a value
    # the cipher does not carry, not a smaller default.
    mise_env=
    by_hand=
    fake_mise_env=
    fake_mise_fail=
    fake_neuralwatt=nw-test
    fake_tinyfish=tf-test
    fake_pat=ghp_test
    fake_work_pat=ghp_work
    fake_key=ssh-key-test

    secrets_env=$home/.config/maki/secrets.env
    token=$home/.config/gh/token
    ssh_key=$home/.ssh/id_smortress
    state=$home/.local/state/dotfiles/secrets.sha256
}

# secrets [args]: the script under test, with the fakes on PATH. by_hand=1 leaves
# MISE_ENV unset, as a shell outside mise does.
secrets() {
    local -a mise=()
    [ -n "$by_hand" ] || mise=("MISE_ENV=$mise_env")
    env -i HOME="$home" PATH="$bin:/usr/bin:/bin" SECRETS_LOG="$log" \
        ${mise[@]+"${mise[@]}"} \
        FAKE_MISE_ENV="$fake_mise_env" FAKE_MISE_FAIL="$fake_mise_fail" \
        FAKE_NEURALWATT="$fake_neuralwatt" FAKE_TINYFISH="$fake_tinyfish" \
        FAKE_PAT="$fake_pat" FAKE_WORK_PAT="$fake_work_pat" \
        FAKE_SMORTRESS_SSH_KEY="$fake_key" \
        DOTFILES_SECRETS="$cipher" \
        sh "$dotfiles_root/scripts/secrets.sh" "$@"
}

# decrypts: how many times the fake sops has run in this test.
decrypts() { grep -c '^sops$' "$log" || true; }

mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

# --- the first decrypt on a personal machine

@test "decrypt exits 0, writes the provider keys, and the token is mode 600" {
    run secrets
    assert_success
    run grep -qx 'NEURALWATT_API_KEY=nw-test' "$secrets_env"
    assert_success
    assert_equal "$(mode_of "$secrets_env")" 600
    assert_equal "$(cat "$token" 2>/dev/null)" ghp_test
    assert_equal "$(mode_of "$token" 2>/dev/null)" 600
}

@test "the PATs stay out of the Maki cache, the output, and gh" {
    run secrets
    assert_success
    refute_output --partial 'ghp_'
    run grep -q ghp_ "$secrets_env"
    assert_failure
    run grep -q '^gh ' "$log"
    assert_failure
}

@test "the smortress key is written where ssh reads it, mode 600 in a private dir" {
    run secrets
    assert_success
    run grep -qx 'ssh-key-test' "$ssh_key"
    assert_success
    assert_equal "$(mode_of "$ssh_key")" 600
    assert_equal "$(mode_of "$home/.ssh")" 700
}

@test "the smortress key stays out of the Maki cache and the output" {
    run secrets
    assert_success
    refute_output --partial 'ssh-key-test'
    run grep -q ssh-key-test "$secrets_env"
    assert_failure
}

# --- one decrypt per change, whatever happens to the files it wrote

@test "an unchanged file skips the second decrypt" {
    run secrets
    assert_success
    run secrets
    assert_success
    assert_equal "$(decrypts)" 1
}

@test "a loosened token file is tightened without decrypting" {
    run secrets
    assert_success
    chmod 644 "$token"
    run secrets
    assert_success
    assert_equal "$(mode_of "$token")" 600
    assert_equal "$(decrypts)" 1
}

@test "a deleted token file is restored without a changed file" {
    run secrets
    assert_success
    rm "$token"
    run secrets
    assert_success
    assert_equal "$(cat "$token" 2>/dev/null)" ghp_test
    assert_equal "$(decrypts)" 2
}

@test "a work machine gets only the work PAT, even with an unchanged file" {
    run secrets
    assert_success
    mise_env=desktop,work
    run secrets
    assert_success
    assert_equal "$(cat "$token" 2>/dev/null)" ghp_work
    assert_equal "$(decrypts)" 2
}

@test "a work machine skips the second decrypt" {
    mise_env=desktop,work
    run secrets
    assert_success
    run secrets
    assert_success
    assert_equal "$(decrypts)" 1
}

@test "a changed file decrypts again" {
    run secrets
    assert_success
    printf 'changed\n' >"$cipher"
    run secrets
    assert_success
    assert_equal "$(decrypts)" 2
}

@test "missing provider keys fail" {
    fake_neuralwatt=
    run secrets
    assert_failure
}

@test "missing provider keys keep the existing file" {
    mkdir -p "$home/.config/maki"
    printf 'old\n' >"$secrets_env"
    printf 'changed\n' >"$cipher"
    fake_neuralwatt=
    run secrets
    assert_failure
    run grep -qx old "$secrets_env"
    assert_success
}

@test "an empty PAT leaves the token file alone" {
    run secrets
    assert_success
    printf 'changed\n' >"$cipher"
    fake_pat=
    run secrets
    assert_success
    assert [ -e "$token" ]
}

@test "an empty PAT warns that git and gh have no token" {
    fake_pat=
    run secrets
    assert_success
    assert_output --partial 'no GITHUB_PERSONAL_PAT'
}

@test "an empty PAT is not decrypted again on every run" {
    run secrets
    assert_success
    printf 'changed\n' >"$cipher"
    fake_pat=
    run secrets
    assert_success
    before=$(decrypts)
    run secrets
    assert_success
    assert_equal "$(decrypts)" "$before"
}

@test "switching to work picks up the work PAT despite the empty personal one" {
    fake_pat=
    run secrets
    assert_success
    mise_env=work
    run secrets
    assert_success
    assert_equal "$(cat "$token" 2>/dev/null)" ghp_work
}

# --- the smortress ssh key
# A fixed work environment keeps these cases on the key marker alone.

@test "an untouched machine does not decrypt for the key again" {
    mise_env=work
    run secrets
    assert_success
    before=$(decrypts)
    run secrets
    assert_success
    assert_equal "$(decrypts)" "$before"
}

@test "a loosened key file is tightened without decrypting" {
    mise_env=work
    run secrets
    assert_success
    chmod 644 "$ssh_key"
    before=$(decrypts)
    run secrets
    assert_success
    assert_equal "$(mode_of "$ssh_key")" 600
    assert_equal "$(decrypts)" "$before"
}

@test "a deleted key file is restored without a changed file" {
    mise_env=work
    run secrets
    assert_success
    rm "$ssh_key"
    before=$(decrypts)
    run secrets
    assert_success
    assert_equal "$(mode_of "$ssh_key")" 600
    assert_equal "$(decrypts)" "$((before + 1))"
}

# A state file from before the key existed carries two fields.
@test "a state file without the key marker decrypts once more" {
    mise_env=work
    run secrets
    assert_success
    sha=$(cut -d' ' -f1 "$state")
    printf '%s %s\n' "$sha" "$(cut -d' ' -f2 "$state")" >"$state"
    before=$(decrypts)
    run secrets
    assert_success
    assert_equal "$(decrypts)" "$((before + 1))"
}

# sops writes a multi-line dotenv value escaped on one line; ssh needs newlines.
@test "a multi-line key value is written as real lines" {
    fake_key='key-line-1\nkey-line-2'
    run secrets
    assert_success
    assert_equal "$(tr '\n' ' ' <"$ssh_key")" 'key-line-1 key-line-2 '
    assert_equal "$(mode_of "$ssh_key")" 600
}

# The key is required, so no cipher may remove it, --prune included.
@test "a cipher without the key fails and leaves the key file alone" {
    run secrets
    assert_success
    printf 'key2\n' >"$cipher"
    fake_key=
    run secrets
    assert_failure
    assert [ -e "$ssh_key" ]
}

@test "a cipher without the key fails under --prune too" {
    run secrets
    assert_success
    printf 'key2\n' >"$cipher"
    fake_key=
    run secrets --prune
    assert_failure
    assert [ -e "$ssh_key" ]
}

@test "the key comes back with the cipher's value" {
    run secrets
    assert_success
    printf 'key2\n' >"$cipher"
    fake_key=
    run secrets
    assert_failure
    fake_key=ssh-key-test
    run secrets
    assert_success
    run grep -qx 'ssh-key-test' "$ssh_key"
    assert_success
}

@test "a machine without the age identity is left alone" {
    run secrets
    assert_success
    rm "$home/.config/sops/keys.age"
    printf 'changed\n' >"$cipher"
    before=$(decrypts)
    run secrets
    assert_success
    assert_equal "$(decrypts)" "$before"
}

# --- an absent key
# An absent key must not delete a credential, because a stale checkout carries an
# older cipher than the one that delivered it. Removal is opt-in.

@test "an absent PAT leaves the token in place and says how to remove it" {
    run secrets
    assert_success
    assert [ -e "$token" ]
    printf 'changed\n' >"$cipher"
    fake_pat=
    run secrets
    assert_success
    assert [ -e "$token" ]
    assert_output --partial '--prune removes it'
}

@test "--prune removes the token" {
    run secrets
    assert_success
    printf 'changed\n' >"$cipher"
    fake_pat=
    run secrets --prune
    assert_success
    refute [ -e "$token" ]
}

# --- a hand run
# A hand run outside mise has no MISE_ENV; the set must come from mise, or a work
# machine silently gets the personal PAT.

@test "a hand run on a work machine gets the work PAT" {
    by_hand=1
    fake_mise_env=desktop,work
    run secrets
    assert_success
    assert_equal "$(cat "$token" 2>/dev/null)" ghp_work
}

@test "a hand run asks mise for the environment set" {
    by_hand=1
    fake_mise_env=desktop,work
    run secrets
    assert_success
    run grep -q '^mise exec' "$log"
    assert_success
}

@test "a hand run where mise has no set gets the personal PAT" {
    by_hand=1
    run secrets
    assert_success
    assert_equal "$(cat "$token" 2>/dev/null)" ghp_test
}

@test "a hand run fails when mise cannot report the set" {
    by_hand=1
    fake_mise_fail=1
    run secrets
    assert_failure
}

@test "a failed mise lookup leaves the token alone and says how to run it" {
    run secrets
    assert_success
    by_hand=1
    fake_mise_fail=1
    printf 'changed\n' >"$cipher"
    run secrets
    assert_failure
    assert_equal "$(cat "$token" 2>/dev/null)" ghp_test
    assert_output --partial 'mise exec -- sh scripts/secrets.sh'
}
