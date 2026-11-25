#!/usr/bin/env bats
# The ~/.local/bin/maki key wrapper: a stand-in binary reports the provider keys
# it received.
load helpers

setup() {
    wrapper=$dotfiles_root/home/.local/bin/maki
    h=$BATS_TEST_TMPDIR/home
    secrets=$h/.config/maki/secrets.env
    mkdir -p "$h/.local/libexec" "$h/.config/maki"
    cat >"$h/.local/libexec/maki" <<'EOF'
#!/bin/sh
printf 'child:%s:%s:%s\n' "${NEURALWATT_API_KEY:-unset}" "${TINYFISH_API_KEY:-unset}" "$*"
EOF
    chmod +x "$h/.local/libexec/maki"
}

# Every shape the old zsh launcher accepted: comments, blank lines, CRLF, spaces
# around =, an export prefix, and one layer of quotes.
write_secrets() {
    printf '# provider keys\r\n\r\n  # indented comment\r\nexport NEURALWATT_API_KEY = "nw-test"  \r\n\r\nTINYFISH_API_KEY=tf-test\r\n' >"$secrets"
    chmod 600 "$secrets"
}

maki() {
    env -i HOME="$h" PATH=/usr/bin:/bin sh "$wrapper" "$@"
}

@test "maki receives the provider keys and its arguments" {
    write_secrets
    run maki --session x
    assert_success
    assert_output "child:nw-test:tf-test:--session x"
}

@test "maki parses the file without complaints" {
    write_secrets
    run --separate-stderr maki
    assert_stderr ""
}

@test "the keys never reach the caller" {
    write_secrets
    run env -i HOME="$h" PATH=/usr/bin:/bin sh -c \
        '"$1" >/dev/null 2>&1; printf %s "${NEURALWATT_API_KEY:-unset}:${TINYFISH_API_KEY:-unset}"' \
        sh "$wrapper"
    assert_output "unset:unset"
}

@test "single quotes are cosmetic too" {
    printf "NEURALWATT_API_KEY='single'\nOTHER=x\nno-equals-here\n" >"$secrets"
    chmod 600 "$secrets"
    run --separate-stderr maki
    assert_success
    assert_output "child:single:unset:"
}

@test "unknown names and lines without = are reported, without values" {
    printf "NEURALWATT_API_KEY='single'\nOTHER=x\nno-equals-here\n" >"$secrets"
    chmod 600 "$secrets"
    run --separate-stderr maki
    assert_stderr "maki: $secrets:2: skipped (OTHER is not a Maki provider key)
maki: $secrets:3: skipped (no =)"
}

@test "a readable secrets file is flagged" {
    write_secrets
    chmod 644 "$secrets"
    run --separate-stderr maki
    assert_stderr --partial 'is mode 644, expected 600'
}

@test "a missing secrets file still starts maki" {
    run --separate-stderr maki
    assert_success
    assert_output "child:unset:unset:"
}

@test "a missing secrets file is reported" {
    run --separate-stderr maki
    assert_stderr --partial 'secrets.env is missing'
}

@test "a missing binary fails with 127" {
    rm "$h/.local/libexec/maki"
    run -127 maki
    assert_equal "$status" 127
}

@test "the failure names the installer" {
    rm "$h/.local/libexec/maki"
    run -127 --separate-stderr maki
    assert_stderr --partial install-maki.sh
}

@test "the installer puts the binary off PATH" {
    [ "$(uname -s)-$(uname -m)" = Linux-x86_64 ] || skip "the installer ships a Linux x86_64 binary only"
    run bash "$dotfiles_root/scripts/install-maki.sh" --dry-run --prefix "$BATS_TEST_TMPDIR/p"
    assert_success
    assert_output --partial "would install $BATS_TEST_TMPDIR/p/libexec/maki"
}
