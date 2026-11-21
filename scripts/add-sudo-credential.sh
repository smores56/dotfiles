#!/bin/sh
# Adds the sudo credentials to this client's agent (design #767, T10/T11).
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
# Everything here is a no-op rather than an error: a machine with no YubiKey and
# an agent whose unit or LaunchAgent has not bound its socket yet are both
# normal, and sudo's password fallback covers them.
set -eu

log() { printf 'bootstrap: %s\n' "$*" >&2; }

sock=$HOME/.local/state/ssh/agent.sock
# The service manager returns before ssh-agent has bound the socket.
i=0
while [ ! -S "$sock" ] && [ "$i" -lt 20 ]; do
    sleep 0.1
    i=$((i + 1))
done
[ -S "$sock" ] || exit 0
SSH_AUTH_SOCK=$sock
export SSH_AUTH_SOCK
# Apple's OpenSSH refuses an sk handle without a FIDO provider; the Linux
# builds find libfido2 on their own.
if [ "$(uname -s)" = Darwin ]; then
    SSH_SK_PROVIDER=/usr/lib/ssh-keychain.dylib
    export SSH_SK_PROVIDER
fi

# Skip only the handles already in the agent, not the whole loop: a key enrolled
# after the first bootstrap has to be added on the next one, and asking "is any
# sk key loaded" answers a different question -- it would leave every spare key
# out and turn its tap into a password prompt. `ssh-add -L` prints the loaded
# keys in authorized_keys form, so the public half decides.
loaded=$(ssh-add -L 2>/dev/null) || loaded=

found=0
for key in "$HOME"/.ssh/id_smortress_sudo*; do
    [ -f "$key" ] || continue
    case $key in
        *.pub) continue ;;
    esac
    found=1
    if [ -f "$key.pub" ] && printf '%s\n' "$loaded" | cut -d' ' -f1,2 |
        grep -qxF "$(cut -d' ' -f1,2 <"$key.pub")"; then
        continue
    fi
    ssh-add "$key" || log "could not add $key; run: ssh-add $key"
done
[ "$found" -eq 1 ] || log "no ~/.ssh/id_smortress_sudo* handle; sudo falls back to the password"
