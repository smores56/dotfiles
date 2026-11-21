#!/bin/sh
# Adds the sudo credentials to the work Mac's agent (design #767, T10/T11).
#
# Enrollment mints one resident sk handle per YubiKey -- id_smortress_sudo_1,
# _2, _3 -- and every one of them goes in: ssh-agent offers each in turn, and
# only the token in the port can answer for its own handle, so an agent holding
# one credential turns a spare key's tap into a password prompt.
#
# ssh-add needs the key present but asks for no touch; the touch happens when
# sudo signs, which is why the bootstrap runs this with a hand at the keyboard
# and no login hook ever does.
#
# Everything here is a no-op rather than an error: a Mac with no YubiKey and a
# launchd agent that has not bound its socket yet are both normal, and sudo's
# password fallback covers them.
set -eu

log() { printf 'bootstrap: %s\n' "$*" >&2; }

[ "$(uname -s)" = Darwin ] || exit 0

sock=$HOME/.local/state/ssh/agent.sock
# launchctl bootstrap returns before ssh-agent has bound the socket.
i=0
while [ ! -S "$sock" ] && [ "$i" -lt 20 ]; do
    sleep 0.1
    i=$((i + 1))
done
[ -S "$sock" ] || exit 0
SSH_AUTH_SOCK=$sock
# Apple's OpenSSH refuses an sk handle without a FIDO provider.
SSH_SK_PROVIDER=/usr/lib/ssh-keychain.dylib
export SSH_AUTH_SOCK SSH_SK_PROVIDER

# `ssh-add -l` prints "… (ED25519-SK)": re-adding on every bootstrap is pure
# friction once a handle is already loaded.
ssh-add -l 2>/dev/null | grep -qi 'ed25519-sk' && exit 0

found=0
for key in "$HOME"/.ssh/id_smortress_sudo*; do
    [ -f "$key" ] || continue
    case $key in
        *.pub) continue ;;
    esac
    found=1
    ssh-add "$key" || log "could not add $key; run: ssh-add $key"
done
[ "$found" -eq 1 ] || log "no ~/.ssh/id_smortress_sudo* handle; sudo falls back to the password"
