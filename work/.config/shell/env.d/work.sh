export SDLC_REPO=smohr-blitzy/sdlc
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
