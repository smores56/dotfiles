#!/usr/bin/env bats
# The wallpaper sync, selection and per-output apply, with fakes for rclone,
# identify, niri, noctalia and tailscale.
load helpers

setup() {
    [ "$(uname -s)" = Linux ] || skip "the wallpaper sync is Linux-only"
    script=$dotfiles_root/desktop/.local/bin/wallpapers
    home=$BATS_TEST_TMPDIR/home
    bin=$BATS_TEST_TMPDIR/bin
    state=$BATS_TEST_TMPDIR/state
    log=$BATS_TEST_TMPDIR/log
    nojq=$BATS_TEST_TMPDIR/nojq
    mkdir -p "$home" "$bin" "$state"

    # tailscale serve publishes https://<node>.<tailnet>.ts.net/<path>; the
    # tailnet suffix is machine-specific, so the script reads it from tailscaled.
    cat >"$bin/tailscale" <<'EOF'
#!/bin/sh
[ "$*" = "status --json" ] || exit 1
[ "${FAKE_TS_FAIL:-}" = 1 ] && exit 1
[ "${FAKE_TS_NONAME:-}" = 1 ] && { printf '{"Self":{}}'; exit 0; }
printf '%s' '{"Self":{"DNSName":"smorespro.tail1234.ts.net."}}'
EOF

    cat >"$bin/rclone" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$RCLONE_LOG"
case $1 in
    lsf)
        [ "${FAKE_LSF_FAIL:-}" = 1 ] && exit 1
        if [ "${FAKE_LSF_NESTED:-}" = 1 ]; then
            # The canonical tree has no top-level files: every image sits in a
            # subdirectory, so --files-only sees an empty listing.
            case " $* " in
                *" --files-only "*) ;;
                *) printf 'Standard/\nUltrawide/\n' ;;
            esac
        else
            printf 'a.jpg\nb.png\nwide.jpg\n'
        fi ;;
    sync)
        mkdir -p "$3"
        if [ "${FAKE_LSF_NESTED:-}" = 1 ]; then
            mkdir -p "$3/Standard" "$3/Ultrawide"
            printf x >"$3/Standard/a.jpg"
            printf y >"$3/Ultrawide/b.png"
        else
            printf x >"$3/a.jpg"
            printf y >"$3/b.png"
            printf z >"$3/wide.jpg"
        fi ;;
esac
EOF

    cat >"$bin/identify" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    case $1 in
        -ping|-quiet) shift ;;
        -format) shift 2 ;;
        *) break ;;
    esac
done
for file do
    case ${file##*/} in
        a.jpg) printf '1920 1080 %s\n' "$file" ;;
        b.png) printf '3440 1440 %s\n' "$file" ;;
        wide.jpg) printf '3840 1600 %s\n' "$file" ;;
        *) exit 1 ;;
    esac
done
EOF

    cat >"$bin/niri" <<'EOF'
#!/bin/sh
[ "${FAKE_NIRI_FAIL:-}" = 1 ] && exit 1
[ "$*" = "msg --json outputs" ] || exit 1
printf '%s' '{"eDP-1":{"current_mode":0,"logical":{"width":1920,"height":1080},"modes":[{"width":1920,"height":1080}]},"DP-1":{"current_mode":0,"logical":{"width":3440,"height":1440},"modes":[{"width":3440,"height":1440}]}}'
EOF

    cat >"$bin/noctalia" <<'EOF'
#!/bin/sh
[ "$1" = msg ] || exit 1
case $2 in
    wallpaper-set) printf '%s\n' "$4" >"$NOCTALIA_STATE/set-$3" ;;
    wallpaper-get) cat "$NOCTALIA_STATE/set-$3" 2>/dev/null ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$bin"/*
}

# wallpapers [args]: run the script with the fakes on PATH. FAKE_* and
# WALLPAPERS_* are read from the test, so a test may set them before the call.
wallpapers() {
    env -i HOME="$home" PATH="${RUN_PATH:-$bin:/usr/bin:/bin}" \
        XDG_CACHE_HOME="$home/.cache" \
        RCLONE_LOG="$log" FAKE_LSF_FAIL="${FAKE_LSF_FAIL:-}" \
        FAKE_LSF_NESTED="${FAKE_LSF_NESTED:-}" \
        FAKE_NIRI_FAIL="${FAKE_NIRI_FAIL:-}" \
        FAKE_TS_FAIL="${FAKE_TS_FAIL:-}" FAKE_TS_NONAME="${FAKE_TS_NONAME:-}" \
        NOCTALIA_STATE="$state" \
        WALLPAPERS_RCLONE="$bin/rclone" \
        WALLPAPERS_CACHE="${WALLPAPERS_CACHE:-}" \
        WALLPAPERS_SOURCE="${WALLPAPERS_SOURCE:-}" \
        sh "$script" "$@"
}

# The apply needs jq, and it must be the same jq the run's PATH reaches.
have_jq() { PATH="$bin:/usr/bin:/bin" command -v jq >/dev/null 2>&1; }

@test "a sync mirrors the served tree into the cache" {
    run wallpapers sync
    assert_success
    assert [ -f "$home/.cache/wallpapers/Wallpapers/a.jpg" ]
}

@test "the sync reads the served URL for the resolved tailnet" {
    run wallpapers sync
    assert_success
    run cat "$log"
    assert_output --partial ":http,url='https://smortress.tail1234.ts.net/wallpapers/':"
}

# The served tree is device-authenticated, so the sync carries no credential.
@test "the sync carries no credential" {
    run wallpapers sync
    assert_success
    assert [ -s "$log" ]
    run grep -E 'key_file|known_hosts|ssh=|user=' "$log"
    assert_failure
}

# A probe that only looks at top-level files reports the canonical tree as
# empty, because every image is nested under an aspect directory.
@test "a tree with only nested files syncs" {
    FAKE_LSF_NESTED=1
    WALLPAPERS_CACHE=$home/.cache/wallpapers-nested
    run wallpapers sync
    assert_success
    assert [ -f "$home/.cache/wallpapers-nested/Wallpapers/Standard/a.jpg" ]
}

@test "WALLPAPERS_SOURCE overrides the served URL" {
    WALLPAPERS_CACHE=$home/.cache/wallpapers2
    WALLPAPERS_SOURCE=https://cache.example.test/wallpapers/
    run wallpapers sync
    assert_success
    run cat "$log"
    assert_output --partial ":http,url='https://cache.example.test/wallpapers/':"
}

@test "a host:path source is refused" {
    WALLPAPERS_CACHE=$home/.cache/wallpapers3
    WALLPAPERS_SOURCE=smortress:/srv/wallpapers/
    run wallpapers sync
    assert_failure
}

@test "an unreadable tailscale status fails the sync" {
    FAKE_TS_FAIL=1
    WALLPAPERS_CACHE=$home/.cache/wallpapers4
    run --separate-stderr wallpapers sync
    assert_failure
    assert_stderr --partial 'cannot read the tailnet name'
}

@test "a node without a MagicDNS name fails the sync" {
    FAKE_TS_NONAME=1
    WALLPAPERS_CACHE=$home/.cache/wallpapers5
    run wallpapers sync
    assert_failure
}

# jq does the parse, so a host without it must hear that, not "cannot read the
# tailnet name". The PATH carries only what the run needs up to the parse, plus
# mktemp and rm for the apply that still runs afterwards and its exit trap, so
# nothing else can be the missing command.
@test "a missing jq fails the sync and is not blamed on tailscaled" {
    mkdir -p "$nojq"
    for tool in sh mkdir flock mktemp rm; do
        ln -sf "$(command -v "$tool")" "$nojq/$tool"
    done
    ln -sf "$bin/tailscale" "$bin/rclone" "$nojq/"
    RUN_PATH=$nojq
    WALLPAPERS_CACHE=$home/.cache/wallpapers6
    run --separate-stderr wallpapers sync
    assert_failure
    assert_stderr --partial 'jq is required'
    refute_stderr --partial 'cannot read the tailnet name'
}

@test "the standard display gets a standard image" {
    have_jq || skip "jq is not installed"
    run wallpapers sync
    assert_success
    run cat "$state/set-eDP-1"
    assert_output --partial /a.jpg
}

@test "the ultrawide display gets an ultrawide image" {
    have_jq || skip "jq is not installed"
    run wallpapers sync
    assert_success
    run cat "$state/set-DP-1"
    assert_output --regexp '/(b\.png|wide\.jpg)$'
}

@test "the two displays do not share one pick" {
    have_jq || skip "jq is not installed"
    run wallpapers sync
    assert_success
    run cat "$state/set-eDP-1"
    edp=$output
    run cat "$state/set-DP-1"
    dp=$output
    assert [ -n "$edp" ]
    assert_not_equal "$edp" "$dp"
}

# Outside a session (greetd, SSH) there is nothing to set: the oneshot must skip
# without failing rather than park in a restart loop.
@test "a run outside a session skips without failing" {
    run wallpapers sync
    assert_success
    FAKE_NIRI_FAIL=1
    run wallpapers apply
    assert_success
}

# The probe runs before the sync, so an unreachable host never empties the cache.
@test "an unreachable source fails the sync" {
    mkdir -p "$home/.cache/wallpapers/Wallpapers"
    printf keep >"$home/.cache/wallpapers/Wallpapers/old.jpg"
    FAKE_LSF_FAIL=1
    run --separate-stderr wallpapers sync
    assert_failure
    assert_stderr --partial 'keeping the cached set'
    assert [ -f "$home/.cache/wallpapers/Wallpapers/old.jpg" ]
}

# pick must not repeat until the list is exhausted.
@test "picks do not repeat while the queue holds entries" {
    list=$BATS_TEST_TMPDIR/list
    queue=$BATS_TEST_TMPDIR/queue
    printf '%s\n' "$BATS_TEST_TMPDIR/one.jpg" "$BATS_TEST_TMPDIR/two.jpg" >"$list"
    run wallpapers pick "$list" "$queue"
    assert_success
    first=$output
    run wallpapers pick "$list" "$queue"
    assert_success
    second=$output
    assert [ -n "$first" ]
    assert [ -n "$second" ]
    assert_not_equal "$first" "$second"
}

@test "the cycle restarts after the list is exhausted" {
    list=$BATS_TEST_TMPDIR/list
    queue=$BATS_TEST_TMPDIR/queue
    printf '%s\n' "$BATS_TEST_TMPDIR/one.jpg" "$BATS_TEST_TMPDIR/two.jpg" >"$list"
    run wallpapers pick "$list" "$queue"
    assert_success
    first=$output
    run wallpapers pick "$list" "$queue"
    assert_success
    second=$output
    run wallpapers pick "$list" "$queue"
    assert_success
    [[ $output == "$first" || $output == "$second" ]]
}

# A failed display must not consume the image.
@test "unpick puts the image back at the head" {
    list=$BATS_TEST_TMPDIR/list
    queue=$BATS_TEST_TMPDIR/queue
    printf '%s\n' "$BATS_TEST_TMPDIR/one.jpg" "$BATS_TEST_TMPDIR/two.jpg" >"$list"
    run wallpapers pick "$list" "$queue"
    assert_success
    run wallpapers unpick "$queue" "$BATS_TEST_TMPDIR/one.jpg"
    assert_success
    run wallpapers pick "$list" "$queue"
    assert_success
    assert_equal "$output" "$BATS_TEST_TMPDIR/one.jpg"
}

@test "buckets separates the images by aspect" {
    img=$BATS_TEST_TMPDIR/img
    out=$BATS_TEST_TMPDIR/out
    mkdir -p "$img"
    printf x >"$img/a.jpg"
    printf y >"$img/b.png"
    printf z >"$img/wide.jpg"
    run wallpapers buckets "$img" "$out"
    assert_success
    assert [ -s "$out/Standard.list" ]
    assert [ -s "$out/Ultrawide.list" ]
    run grep -q 'a.jpg' "$out/Standard.list"
    assert_success
    run grep -q 'b.png' "$out/Ultrawide.list"
    assert_success
}
