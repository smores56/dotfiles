#!/usr/bin/env bash
# The wallpaper sync, selection and per-output apply, with fakes for rclone,
# identify, niri, noctalia and tailscale.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

[ "$(uname -s)" = Linux ] || skip_all "the wallpaper sync is Linux-only"

script=$root/desktop/.local/bin/wallpapers
home=$tmp/home
mkdir -p "$home" "$tmp/bin" "$tmp/state"

# tailscale serve publishes https://<node>.<tailnet>.ts.net/<path>; the tailnet
# suffix is machine-specific, so the script reads it from tailscaled.
cat >"$tmp/bin/tailscale" <<'EOF'
#!/bin/sh
[ "$*" = "status --json" ] || exit 1
[ "${FAKE_TS_FAIL:-}" = 1 ] && exit 1
[ "${FAKE_TS_NONAME:-}" = 1 ] && { printf '{"Self":{}}'; exit 0; }
printf '%s' '{"Self":{"DNSName":"smorespro.tail1234.ts.net."}}'
EOF

cat >"$tmp/bin/rclone" <<'EOF'
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

cat >"$tmp/bin/identify" <<'EOF'
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

cat >"$tmp/bin/niri" <<'EOF'
#!/bin/sh
[ "${FAKE_NIRI_FAIL:-}" = 1 ] && exit 1
[ "$*" = "msg --json outputs" ] || exit 1
printf '%s' '{"eDP-1":{"current_mode":0,"logical":{"width":1920,"height":1080},"modes":[{"width":1920,"height":1080}]},"DP-1":{"current_mode":0,"logical":{"width":3440,"height":1440},"modes":[{"width":3440,"height":1440}]}}'
EOF

cat >"$tmp/bin/noctalia" <<'EOF'
#!/bin/sh
[ "$1" = msg ] || exit 1
case $2 in
    wallpaper-set) printf '%s\n' "$4" >"$NOCTALIA_STATE/set-$3" ;;
    wallpaper-get) cat "$NOCTALIA_STATE/set-$3" 2>/dev/null ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin"/*

run() {
    env -i HOME="$home" PATH="${RUN_PATH:-$tmp/bin:/usr/bin:/bin}" XDG_CACHE_HOME="$home/.cache" \
        RCLONE_LOG="$tmp/log" FAKE_LSF_FAIL="${FAKE_LSF_FAIL:-}" \
        FAKE_LSF_NESTED="${FAKE_LSF_NESTED:-}" \
        FAKE_NIRI_FAIL="${FAKE_NIRI_FAIL:-}" \
        FAKE_TS_FAIL="${FAKE_TS_FAIL:-}" FAKE_TS_NONAME="${FAKE_TS_NONAME:-}" \
        NOCTALIA_STATE="$tmp/state" \
        WALLPAPERS_RCLONE="$tmp/bin/rclone" \
        WALLPAPERS_CACHE="${WALLPAPERS_CACHE:-}" \
        WALLPAPERS_SOURCE="${WALLPAPERS_SOURCE:-}" \
        sh "$script" "$@"
}

assert "sync exits 0" run sync
assert "the cache holds the synced files" test -f "$home/.cache/wallpapers/Wallpapers/a.jpg"
contains "the sync reads the served URL for the resolved tailnet" \
    ":http,url='https://smortress.tail1234.ts.net/wallpapers/':" "$(cat "$tmp/log")"
assert_not "the sync carries no credential" grep -E 'key_file|known_hosts|ssh=|user=' "$tmp/log"

# A probe that only looks at top-level files reports the canonical tree as
# empty, because every image is nested under an aspect directory.
FAKE_LSF_NESTED=1 WALLPAPERS_CACHE="$home/.cache/wallpapers-nested" \
    assert "a tree with only nested files syncs" run sync
assert "a nested image lands in the cache" \
    test -f "$home/.cache/wallpapers-nested/Wallpapers/Standard/a.jpg"

WALLPAPERS_CACHE="$home/.cache/wallpapers2" \
    WALLPAPERS_SOURCE=https://cache.example.test/wallpapers/ run sync >/dev/null 2>&1
contains "WALLPAPERS_SOURCE overrides the served URL" \
    ":http,url='https://cache.example.test/wallpapers/':" "$(cat "$tmp/log")"

WALLPAPERS_CACHE="$home/.cache/wallpapers3" WALLPAPERS_SOURCE=smortress:/srv/wallpapers/ \
    assert_not "a host:path source is refused" run sync

FAKE_TS_FAIL=1 WALLPAPERS_CACHE="$home/.cache/wallpapers4" \
    assert_not "an unreadable tailscale status fails the sync" run sync
contains "the failure names the missing tailnet name" 'cannot read the tailnet name' "$out"

FAKE_TS_NONAME=1 WALLPAPERS_CACHE="$home/.cache/wallpapers5" \
    assert_not "a node without a MagicDNS name fails the sync" run sync

# jq does the parse, so a host without it must hear that, not "cannot read the
# tailnet name". The PATH carries only what the run needs before the parse.
nojq=$tmp/nojq
mkdir -p "$nojq"
for tool in sh mkdir flock; do
    ln -sf "$(command -v "$tool")" "$nojq/$tool"
done
ln -sf "$tmp/bin/tailscale" "$tmp/bin/rclone" "$nojq/"
RUN_PATH=$nojq WALLPAPERS_CACHE="$home/.cache/wallpapers6" \
    assert_not "a missing jq fails the sync" run sync
contains "the failure names the missing jq" 'jq is required' "$out"
assert_not "a missing jq does not blame tailscaled" grep -q 'cannot read the tailnet name' <<<"$out"


if PATH="$tmp/bin:/usr/bin:/bin" command -v jq >/dev/null 2>&1; then
    got_edp=$(cat "$tmp/state/set-eDP-1" 2>/dev/null)
    got_dp=$(cat "$tmp/state/set-DP-1" 2>/dev/null)
    contains "the standard display gets a standard image" /a.jpg "$got_edp"
    case $got_dp in
        */b.png|*/wide.jpg) ok "the ultrawide display gets an ultrawide image" ;;
        *) no "the ultrawide display gets an ultrawide image (got '$got_dp')" ;;
    esac
    assert "the two displays do not share one pick" test -n "$got_edp" -a "$got_edp" != "$got_dp"
else
    printf 'skip apply assertions: jq is not installed\n'
fi

FAKE_NIRI_FAIL=1 assert "a run outside a session skips without failing" run apply

printf keep >"$home/.cache/wallpapers/Wallpapers/old.jpg"
FAKE_LSF_FAIL=1 assert_not "an unreachable source fails the sync" run sync
assert "an unreachable source keeps the cache" test -f "$home/.cache/wallpapers/Wallpapers/old.jpg"

# pick must not repeat until the list is exhausted.
list=$tmp/list
queue=$tmp/queue
printf '%s\n' "$tmp/one.jpg" "$tmp/two.jpg" >"$list"
first=$(run pick "$list" "$queue") || no "the first pick succeeds"
second=$(run pick "$list" "$queue") || no "the second pick succeeds"
assert "picks do not repeat while the queue holds entries" \
    test -n "$first" -a -n "$second" -a "$first" != "$second"
third=$(run pick "$list" "$queue") || no "the cycle restarts"
case $third in
    "$first"|"$second") ok "the cycle restarts after the list is exhausted" ;;
    *) no "the cycle restarts after the list is exhausted (got '$third')" ;;
esac

# A failed display must not consume the image.
run unpick "$queue" "$tmp/one.jpg" >/dev/null 2>&1
head=$(run pick "$list" "$queue") || no "pick after unpick succeeds"
expect "unpick puts the image back at the head" "$tmp/one.jpg" "$head"

mkdir -p "$tmp/img"
printf x >"$tmp/img/a.jpg"; printf y >"$tmp/img/b.png"; printf z >"$tmp/img/wide.jpg"
assert "buckets exits 0" run buckets "$tmp/img" "$tmp/out"
assert "buckets writes both aspect lists" test -s "$tmp/out/Standard.list" -a -s "$tmp/out/Ultrawide.list"
assert "16:9 lands in Standard" grep -q 'a.jpg' "$tmp/out/Standard.list"
assert "21:9 lands in Ultrawide" grep -q 'b.png' "$tmp/out/Ultrawide.list"

finish
