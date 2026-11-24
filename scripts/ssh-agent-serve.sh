#!/bin/sh
# Runs the ssh-agent the sudo tap needs on the work Mac (design #767).
#
# launchd has no ExecStartPost: the plist can start an agent, but nothing loads
# the credentials into it, so every reboot left an empty agent and every sudo
# afterwards silently cost a password -- the failure is a bare "None of these
# keys passed authentication" in pam_rssh's log, with no per-key lines, because
# the agent answered with no keys at all.
#
# The Linux laptops get the same behaviour from the systemd unit's
# ExecStartPost, which needs no script. Here the agent runs in the foreground
# for KeepAlive and the loader runs in between: a resident sk handle loads
# without a touch, so an agent that starts with them costs nothing.
set -eu

sock=$HOME/.local/state/ssh/agent.sock
log() { printf 'ssh-agent-serve: %s\n' "$*" >&2; }

umask 077
mkdir -p "$(dirname "$sock")"
# ssh-agent -a refuses a socket left behind by a crash, and KeepAlive would then
# restart it into the same failure forever.
rm -f "$sock"

# The agent signs the sk handle for pam_rssh, so Apple's FIDO middleware has to be
# in its environment: launchd starts this script with none, and the shell export in
# work.sh reaches only processes a shell starts. Without it the agent cannot sign,
# and every sudo falls back to the password with nothing but pam_rssh's bare
# "None of these keys passed authentication" to show for it.
if [ "$(uname -s)" = Darwin ]; then
    SSH_SK_PROVIDER=${SSH_SK_PROVIDER:-/usr/lib/ssh-keychain.dylib}
    export SSH_SK_PROVIDER
fi

/usr/bin/ssh-agent -D -a "$sock" &
agent=$!
trap 'kill "$agent" 2>/dev/null || true' EXIT TERM INT

# The loader waits for the socket itself; the longer ceiling covers launchd
# returning as soon as the agent is forked.
SUDO_CREDENTIAL_WAIT=100
export SUDO_CREDENTIAL_WAIT
sh "$(dirname "$0")/add-sudo-credential.sh" || log "could not load the sudo credentials"

# Wait on the agent rather than exiting: KeepAlive would restart this job and
# each restart unlinks the live socket.
wait "$agent"
