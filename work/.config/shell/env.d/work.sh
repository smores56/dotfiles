export SDLC_REPO=smohr-blitzy/sdlc
# smortress's sudo gate asks the client's ssh-agent for a signature (design
# #767), so the agent has to be reachable from every shell: the work Mac runs it
# as a LaunchAgent on a fixed socket rather than one socket per terminal. Only
# exported when the daemon has bound it; an inherited agent (inside an ssh
# session, say) then keeps working instead of being pointed at a dead path.
if [ -S "$HOME/.local/state/ssh/agent.sock" ]; then
    SSH_AUTH_SOCK=$HOME/.local/state/ssh/agent.sock
    export SSH_AUTH_SOCK
fi

# The cc crate and native builds use Apple clang (see ~/.cargo/config.toml).
export CC=/usr/bin/clang
export CXX=/usr/bin/clang++

# The employer's ~/.zshrc and the fish bridge expect brew on PATH even in
# non-login shells. It goes after the system paths, so a brew tool never
# shadows a mise one.
case ":$PATH:" in
    *:/opt/homebrew/bin:*) ;;
    *) [ -d /opt/homebrew/bin ] && PATH=$PATH:/opt/homebrew/bin:/opt/homebrew/sbin ;;
esac
export PATH
