#!/usr/bin/env bash
# Install the Maki release pinned in maki/pin.env into ~/.local/libexec, off
# PATH, behind the ~/.local/bin/maki key wrapper. The tarball must match both
# the pin and the release's sha256sums.txt, or nothing is installed.
set -euo pipefail

repo=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
prefix=${HOME:+$HOME/.local}
dry_run=false

fail() { printf 'install-maki: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
usage: install-maki.sh [--prefix DIR] [--dry-run]

  --prefix DIR  install into DIR/libexec (default: ~/.local)
  --dry-run     print the download URL and checksum; write nothing
EOF
}

while [ $# -gt 0 ]; do
    case $1 in
        --prefix)
            [ $# -ge 2 ] || { printf 'install-maki: --prefix needs a value\n' >&2; exit 2; }
            prefix=$2
            shift 2 ;;
        --prefix=*) prefix=${1#*=}; shift ;;
        --dry-run) dry_run=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'install-maki: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

[ -n "$prefix" ] || { printf 'install-maki: no prefix: set HOME or pass --prefix\n' >&2; exit 2; }

# shellcheck source=/dev/null
. "$repo/maki/pin.env"

: "${MAKI_VERSION:?pin.env must set MAKI_VERSION}"
: "${MAKI_TARGET:?pin.env must set MAKI_TARGET}"
: "${MAKI_SHA256:?pin.env must set MAKI_SHA256}"
: "${MAKI_REPO:?pin.env must set MAKI_REPO}"

case $(uname -s)-$(uname -m) in
    Linux-x86_64) ;;
    *) fail "no pinned build for $(uname -s)-$(uname -m); only linux-x86_64 is pinned ($MAKI_TARGET)" ;;
esac

asset="maki-${MAKI_VERSION}-${MAKI_TARGET}.tar.gz"
base="https://github.com/${MAKI_REPO}/releases/download/${MAKI_VERSION}"
url="${base}/${asset}"
sums_url="${base}/sha256sums.txt"
dest=$prefix/libexec/maki

if $dry_run; then
    printf 'would download %s\n' "$url"
    printf 'would verify sha256 %s\n' "$MAKI_SHA256"
    printf 'would install %s\n' "$dest"
    exit 0
fi

work=$(mktemp -d) || fail "cannot create a temporary directory"
trap 'rm -rf "$work"' EXIT HUP INT TERM

curl -fL --proto '=https' --tlsv1.2 -o "$work/$asset" "$url" \
    || fail "could not download $url"
curl -fL --proto '=https' --tlsv1.2 -o "$work/sha256sums.txt" "$sums_url" \
    || fail "could not download $sums_url; refusing to install without a published checksum"

got=$({ sha256sum "$work/$asset" 2>/dev/null || shasum -a 256 "$work/$asset"; } | awk '{ print $1 }')
[ "$got" = "$MAKI_SHA256" ] \
    || fail "$asset is $got, not the pinned $MAKI_SHA256"

published=$(awk -v name="$asset" '$2 == name { print $1; exit }' "$work/sha256sums.txt")
[ -n "$published" ] \
    || fail "sha256sums.txt has no entry for $asset"
[ "$published" = "$MAKI_SHA256" ] \
    || fail "sha256sums.txt publishes $published for $asset, not the pinned $MAKI_SHA256"

tar -xzf "$work/$asset" -C "$work" || fail "could not extract $asset"
binary=$(find "$work" -type f -name maki -perm -u+x | head -n 1)
[ -n "$binary" ] || fail "$asset contains no maki executable"

mkdir -p "$prefix/libexec"
install -m 0755 "$binary" "$dest.tmp"
mv -- "$dest.tmp" "$dest"
printf 'installed maki %s at %s\n' "$MAKI_VERSION" "$dest"
