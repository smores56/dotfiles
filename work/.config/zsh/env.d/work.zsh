# smoreswork's environment for every zsh (agents, launchd jobs, and editors
# run `zsh -c`): what the employer's toolchains expect, nothing else.
export TERMINAL=wezterm
# The work GitHub account owns its SDLC registry.
export SDLC_REPO=smohr-blitzy/sdlc
# Tools that ignore ssh_config's IdentityAgent (libssh2, docker --ssh) find the
# 1Password agent here.
export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
export COLORTERM=truecolor
# The cc crate and native builds use Apple's clang (see ~/.cargo/config.toml).
export CC=/usr/bin/clang
export CXX=/usr/bin/clang++
# The employer's ~/.zshrc expects brew on PATH even in non-login shells.
[[ -d /opt/homebrew/bin ]] && path+=(/opt/homebrew/bin /opt/homebrew/sbin)
for _d in "$HOME/.cargo/bin" "$HOME/.bun/bin" "$HOME/.deno/bin"; do
  [[ -d $_d ]] && path+=("$_d")
done
unset _d
