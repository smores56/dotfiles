# smortress's sudo gate signs through this machine's ssh-agent (design #767),
# so every shell needs the agent's socket. Both agents — a systemd user unit on
# Linux, a LaunchAgent on the work Mac — bind the same path, so one export
# covers them. Only exported when the socket exists: inside an ssh session that
# forwarded an agent, the inherited SSH_AUTH_SOCK is the one that works.
_ssh_agent_sock=${XDG_STATE_HOME:-$HOME/.local/state}/ssh/agent.sock
if [ -S "$_ssh_agent_sock" ]; then
    SSH_AUTH_SOCK=$_ssh_agent_sock
    export SSH_AUTH_SOCK
fi
unset _ssh_agent_sock
