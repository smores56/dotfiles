#!/usr/bin/env bash
# Behavioural tests for the wallpaper sync, with a fake rclone.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }

home=$tmp/home
mkdir -p "$home/.ssh" "$home/.config/ssh" "$tmp/bin"
: >"$home/.ssh/key"
: >"$home/.config/ssh/known_hosts"

cat >"$tmp/bin/rclone" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$RCLONE_LOG"
case $1 in
    lsf)
        [ "${FAKE_LSF_FAIL:-}" = 1 ] && exit 1
        printf 'a.jpg\nb.png\n' ;;
    sync)
        mkdir -p "$3"
        printf x >"$3/a.jpg"
        printf y >"$3/b.png" ;;
esac
EOF
chmod +x "$tmp/bin/rclone"

run() {
    env -i HOME="$home" PATH=/usr/bin:/bin XDG_CACHE_HOME="$home/.cache" \
        RCLONE_LOG="$tmp/log" FAKE_LSF_FAIL="${FAKE_LSF_FAIL:-}" \
        WALLPAPERS_RCLONE="$tmp/bin/rclone" \
        WALLPAPERS_KEY="$home/.ssh/key" \
        WALLPAPERS_KNOWN_HOSTS="$home/.config/ssh/known_hosts" \
        sh "$root/desktop/.local/bin/wallpapers" "$@"
}

if out=$(run sync-and-pick 2>&1); then
    ok "sync-and-pick exits 0"
else
    no "sync-and-pick exits 0"
    printf '%s\n' "$out" | sed 's/^/     /' >&2
fi
[ -f "$home/.cache/wallpapers/Wallpapers/a.jpg" ] \
    && ok "the cache holds the synced files" || no "the cache holds the synced files"
case $out in
    *selected\ *) ok "a wallpaper is selected" ;;
    *) no "a wallpaper is selected" ;;
esac

if grep -q ':sftp,host=smortress,user=core,known_hosts_file=.*,key_file=.*:/srv/wallpapers/' "$tmp/log"; then
    ok "rclone gets the pinned host, key, and known_hosts"
else
    no "rclone gets the pinned host, key, and known_hosts"
    sed 's/^/     /' "$tmp/log" >&2
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
