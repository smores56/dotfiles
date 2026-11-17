#!/usr/bin/env bash
# Behavioural tests for the wallpaper sync, selection and per-output apply,
# with fakes for rclone, identify, niri and noctalia.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
script=$root/desktop/.local/bin/wallpapers
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }

home=$tmp/home
mkdir -p "$home/.ssh" "$home/.config/ssh" "$tmp/bin" "$tmp/state"
: >"$home/.ssh/key"
: >"$home/.config/ssh/known_hosts"

cat >"$tmp/bin/rclone" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$RCLONE_LOG"
case $1 in
    lsf)
        [ "${FAKE_LSF_FAIL:-}" = 1 ] && exit 1
        printf 'a.jpg\nb.png\nwide.jpg\n' ;;
    sync)
        mkdir -p "$3"
        printf x >"$3/a.jpg"
        printf y >"$3/b.png"
        printf z >"$3/wide.jpg" ;;
esac
EOF

cat >"$tmp/bin/identify" <<'EOF'
#!/bin/sh
for last; do :; done
case ${last##*/} in
    a.jpg) printf '1920 1080' ;;
    b.png) printf '3440 1440' ;;
    wide.jpg) printf '3840 1600' ;;
    *) exit 1 ;;
esac
EOF

cat >"$tmp/bin/niri" <<'EOF'
#!/bin/sh
[ "$*" = "msg --json outputs" ] || exit 1
printf '%s' '{"eDP-1":{"current_mode":0,"modes":[{"width":1920,"height":1080}]},"DP-1":{"current_mode":0,"modes":[{"width":3440,"height":1440}]}}'
EOF

cat >"$tmp/bin/noctalia" <<'EOF'
#!/bin/sh
# msg wallpaper-set <connector> <path> | msg wallpaper-get <connector>
[ "$1" = msg ] || exit 1
case $2 in
    wallpaper-set)
        printf '%s\n' "$4" >"$NOCTALIA_STATE/set-$3" ;;
    wallpaper-get)
        cat "$NOCTALIA_STATE/set-$3" 2>/dev/null ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/rclone" "$tmp/bin/identify" "$tmp/bin/niri" "$tmp/bin/noctalia"

run() {
    env -i HOME="$home" PATH="$tmp/bin:/usr/bin:/bin" XDG_CACHE_HOME="$home/.cache" \
        RCLONE_LOG="$tmp/log" FAKE_LSF_FAIL="${FAKE_LSF_FAIL:-}" \
        NOCTALIA_STATE="$tmp/state" \
        WALLPAPERS_RCLONE="$tmp/bin/rclone" \
        WALLPAPERS_KEY="$home/.ssh/key" \
        WALLPAPERS_KNOWN_HOSTS="$home/.config/ssh/known_hosts" \
        sh "$script" "$@"
}

if out=$(run sync 2>&1); then
    ok "sync exits 0"
else
    no "sync exits 0"
    printf '%s\n' "$out" | sed 's/^/     /' >&2
fi
[ -f "$home/.cache/wallpapers/Wallpapers/a.jpg" ] \
    && ok "the cache holds the synced files" || no "the cache holds the synced files"

if grep -q ':sftp,host=smortress,user=core,known_hosts_file=.*,key_file=.*:/srv/wallpapers/' "$tmp/log"; then
    ok "rclone gets the pinned host, key, and known_hosts"
else
    no "rclone gets the pinned host, key, and known_hosts"
    sed 's/^/     /' "$tmp/log" >&2
fi

if command -v jq >/dev/null 2>&1; then
    got_edp=$(cat "$tmp/state/set-eDP-1" 2>/dev/null)
    got_dp=$(cat "$tmp/state/set-DP-1" 2>/dev/null)
    case $got_edp in
        */a.jpg) ok "the standard display gets a standard image" ;;
        *) no "the standard display gets a standard image (got '$got_edp')" ;;
    esac
    case $got_dp in
        */b.png|*/wide.jpg) ok "the ultrawide display gets an ultrawide image" ;;
        *) no "the ultrawide display gets an ultrawide image (got '$got_dp')" ;;
    esac
    [ -n "$got_edp" ] && [ "$got_edp" != "$got_dp" ] \
        && ok "the two displays do not share one pick" \
        || no "the two displays do not share one pick"
else
    printf 'skip apply assertions: jq is not installed\n'
fi

printf keep >"$home/.cache/wallpapers/Wallpapers/old.jpg"
if FAKE_LSF_FAIL=1 run sync 2>/dev/null; then
    no "an unreachable source fails the sync"
else
    ok "an unreachable source fails the sync"
fi
[ -f "$home/.cache/wallpapers/Wallpapers/old.jpg" ] \
    && ok "an unreachable source keeps the cache" \
    || no "an unreachable source keeps the cache"

# Selection: pick must not repeat until the list is exhausted.
list=$tmp/list
queue=$tmp/queue
state=$tmp/buckets
mkdir -p "$state"
printf '%s\n' "$tmp/one.jpg" "$tmp/two.jpg" >"$list"
first=$(run pick "$list" "$queue") || no "the first pick succeeds"
second=$(run pick "$list" "$queue") || no "the second pick succeeds"
[ -n "$first" ] && [ -n "$second" ] && [ "$first" != "$second" ] \
    && ok "picks do not repeat while the queue holds entries" \
    || no "picks do not repeat while the queue holds entries"
third=$(run pick "$list" "$queue") || no "the cycle restarts"
case $third in
    "$first"|"$second") ok "the cycle restarts after the list is exhausted" ;;
    *) no "the cycle restarts after the list is exhausted (got '$third')" ;;
esac

# A failed display must not consume the image.
run unpick "$queue" "$tmp/one.jpg" >/dev/null 2>&1
head=$(run pick "$list" "$queue") || no "pick after unpick succeeds"
[ "$head" = "$tmp/one.jpg" ] \
    && ok "unpick puts the image back at the head" \
    || no "unpick puts the image back at the head (got '$head')"

# Bucketing by measured pixels.
mkdir -p "$tmp/img"
printf x >"$tmp/img/a.jpg"; printf y >"$tmp/img/b.png"; printf z >"$tmp/img/wide.jpg"
run buckets "$tmp/img" "$tmp/out" >/dev/null 2>&1 \
    && ok "buckets exits 0" || no "buckets exits 0"
[ -s "$tmp/out/Standard.list" ] && [ -s "$tmp/out/Ultrawide.list" ] \
    && ok "buckets writes both aspect lists" \
    || no "buckets writes both aspect lists"
grep -q 'a.jpg' "$tmp/out/Standard.list" \
    && ok "16:9 lands in Standard" || no "16:9 lands in Standard"
grep -q 'b.png' "$tmp/out/Ultrawide.list" \
    && ok "21:9 lands in Ultrawide" || no "21:9 lands in Ultrawide"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
