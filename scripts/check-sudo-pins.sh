#!/bin/sh
# Compares this machine's sudo handles with the set smortress pins (design
# #797), on disk and in the agent that actually signs: an unpinned handle
# authenticates nothing -- its tap falls through to the password -- and a pin
# this machine cannot answer leaves a retired key authorized for root. Both are
# silent at use time, so they are loud here.
set -eu

log() { printf 'check-sudo-pins: %s\n' "$*" >&2; }

# The image is the authority for who may sudo, so the check reads it from the
# homelab-platform checkout through the knob the SOPS audit already uses. The
# work Mac has none: work access there is https, and its own handles arrive
# with enrollment.
pins=${SUDO_PINS_FILE:-${HOMELAB_REPO:-/srv/git/github.com/smores56/homelab-platform/main}/image/rootfs/etc/ssh/sudo_authorized_keys}
[ -f "$pins" ] || { log "no pins at $pins; not checking"; exit 0; }
[ -r "$pins" ] || { log "cannot read $pins"; exit 2; }

# Comments, blanks and the duplicate lines a re-run of the enrollment command
# leaves decide nothing: the key material does. A file that pins nothing is a
# broken authority, not a clean machine, and must fail rather than swallow
# every handle as already seen.
tmp=$(mktemp -d) || { log 'cannot make a temporary directory'; exit 2; }
trap 'rm -rf "$tmp"' EXIT
pin=$tmp/pin
awk 'NF >= 2 && $1 !~ /^#/ {
        k = $1 " " $2
        if (!(k in seen)) { seen[k]; print k "\t" (NF >= 3 ? $3 : "key " substr($2, 1, 20)) }
    }' "$pins" >"$pin"
if [ ! -s "$pin" ]; then
    log "$pins holds no keys; cannot check"
    exit 1
fi

# Enrolled handles on disk. Editor backups and temp files share the prefix, so
# the suffix is empty (the legacy single handle) or _ followed by digits -- the
# same name rule the loader applies.
local=$tmp/local
: >"$local"
for key in "$HOME"/.ssh/id_smortress_sudo*; do
    [ -f "$key" ] || continue
    case $key in *.pub) continue ;; esac
    suffix=${key##*/id_smortress_sudo}
    case $suffix in
        '') ;;
        _[0-9]*)
            case ${suffix#_} in
                *[!0-9]*) continue ;;
            esac
            ;;
        *) continue ;;
    esac
    if [ ! -f "$key.pub" ]; then
        # Enrollment writes the public half beside the handle; without it the
        # two sets cannot be compared, which is itself drift.
        log "$(basename "$key") has no .pub; cannot compare it"
        drift=1
        continue
    fi
    # <type> <blob> is the key; the trailing comment is only a label.
    read -r type blob comment <"$key.pub" || true
    if [ -z "${type:-}" ] || [ -z "${blob:-}" ]; then
        log "$(basename "$key").pub holds no key; cannot compare it"
        drift=1
        continue
    fi
    # The label is the comment (smores-sudo-keyN) rather than a filename; it is
    # what both the image and the handle carry, so drift names one thing.
    printf '%s\t%s\n' "$type $blob" "${comment:-$(basename "$key")}" >>"$local"
done

# What the agent serves is what sudo signs with: a handle ssh-add refused, or an
# extra key someone loaded, changes the answer. A socket that does not answer is
# the loader's own logged failure, so it is one line here, not a second failure.
served=$tmp/served
: >"$served"
if [ -S "$HOME/.local/state/ssh/agent.sock" ]; then
    if [ "$(uname -s)" = Darwin ]; then
        SSH_SK_PROVIDER=${SSH_SK_PROVIDER:-/usr/lib/ssh-keychain.dylib}
        export SSH_SK_PROVIDER
    fi
    if out=$(SSH_AUTH_SOCK=$HOME/.local/state/ssh/agent.sock ssh-add -L 2>"$tmp/add.err"); then
        printf '%s\n' "$out" |
            awk 'NF >= 2 { print $1 " " $2 "\t" (NF >= 3 ? $3 : "key " substr($2, 1, 20)) }' >"$served"
    elif [ "$?" -le 1 ]; then
        log 'the agent holds no keys; sudo falls back to the password'
    else
        log 'the agent did not answer; cannot check what it holds'
    fi
fi

# A handle that could not be read is already drift; the benign exit is only for
# a machine with nothing enrolled and no agent key at all.
if [ ! -s "$local" ] && [ ! -s "$served" ] && [ "${drift:-0}" -eq 0 ]; then
    log 'no ~/.ssh/id_smortress_sudo* handle and no agent key; nothing to compare'
    exit 0
fi

# One direction per line pair: a pinned key missing from a local set, and a
# local key the image does not pin. The label is the comment when there is one.
report_missing() {  # report_missing <pinned set> <other set> <message>
    awk -F'\t' -v msg="$3" '
        FNR == NR { seen[$1]; next }
        !($1 in seen) { printf "check-sudo-pins: " msg "\n", $2 > "/dev/stderr"; bad = 1 }
        END { exit bad }
    ' "$1" "$2"
}
pinned_but_unheld='%s is pinned on smortress but has no handle here; that key cannot sudo from this machine'
pinned_but_unserved='%s is pinned on smortress but the agent does not hold it; sudo falls back to the password'
unpinned='%s is not pinned on smortress; its touch falls back to the password'

# The on-disk handles: what a rebuild copies, and what the loader will load.
report_missing "$local" "$pin" "$pinned_but_unheld" || drift=1
report_missing "$pin" "$local" "$unpinned" || drift=1
# The agent: the same question for the keys that can actually sign.
report_missing "$served" "$pin" "$pinned_but_unserved" || drift=1
report_missing "$pin" "$served" "$unpinned" || drift=1

[ "${drift:-0}" -eq 0 ] || {
    log 'fix the drift: fetch the resident handles with ssh-keygen -K and rename them id_smortress_sudo_<n>, or pin/retire the key in image/rootfs/etc/ssh/sudo_authorized_keys (fetch that checkout first)'
    exit 1
}
exit 0
