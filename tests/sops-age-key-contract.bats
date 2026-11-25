#!/usr/bin/env bats
# The routing in sops-age-key depends on sops passing the stanza's recipient in
# SOPS_AGE_RECIPIENT. Pin that contract against a real sops and age; skip where
# either is missing.
load helpers

setup_file() {
    if ! command -v sops >/dev/null 2>&1 || ! command -v age-keygen >/dev/null 2>&1; then
        export sops_skip="sops or age-keygen not installed"
        return 0
    fi
    work=$BATS_FILE_TMPDIR/fixture
    mkdir -p "$work"
    if ! age-keygen -o "$work/id.txt" 2>/dev/null; then
        export sops_skip="age-keygen failed"
        return 0
    fi
    recip=$(age-keygen -y "$work/id.txt" 2>/dev/null) || {
        export sops_skip="age-keygen -y failed"
        return 0
    }
    export recip
    cat >"$work/.sops.yaml" <<EOF
creation_rules:
  - path_regex: .*
    key_groups:
      - age:
          - $recip
EOF
    printf 'secret: value\n' >"$work/plain.yaml"
    if ! (cd "$work" && env -i HOME="$work" XDG_CONFIG_HOME="$work/.config" PATH="$PATH" \
            sops --encrypt --input-type yaml --output-type yaml plain.yaml >enc.yaml 2>enc.err); then
        export sops_skip="sops encrypt failed: $(tr '\n' ' ' <"$work/enc.err")"
        return 0
    fi
    export fixture=$work
}

setup() {
    [ -z "${sops_skip:-}" ] || skip "$sops_skip"
    work=$BATS_TEST_TMPDIR/sops
    cp -a "$fixture" "$work"
    # The command logs the recipient sops hands it, and the log is per test so
    # parallel runs never share it.
    cat >"$work/keycmd" <<EOF
#!/bin/sh
printf '%s\n' "\$SOPS_AGE_RECIPIENT" >> "$work/log"
cat "$work/id.txt"
EOF
    chmod +x "$work/keycmd"
    : >"$work/log"
}

decrypt() {
    cd "$work" || return 1
    env -i HOME="$work" XDG_CONFIG_HOME="$work/.config" PATH="$PATH" \
        SOPS_AGE_KEY_CMD="$work/keycmd" sops --decrypt \
        --input-type yaml --output-type yaml enc.yaml
}

@test "sops decrypts through SOPS_AGE_KEY_CMD" {
    run decrypt
    assert_success
}

@test "the plaintext survives the round trip" {
    run decrypt
    assert_output --partial 'secret: value'
}

@test "sops passes the stanza recipient to the command" {
    decrypt >/dev/null 2>&1
    run cat "$work/log"
    assert_output --partial "$recip"
}

@test "the command runs once for a one-recipient file" {
    decrypt >/dev/null 2>&1
    run grep -c . "$work/log"
    assert_output 1
}
