# Work host
- This is a work host: work checkouts live flat in `/Users/sam/Blitzy` (`$BLITZY_REPOS_DIR`); `repos get` routes the GitHub owners `blitzy-ai`, `blitzy-platform` there directly, and `repos list` includes both roots
- The work tooling's shell functions and aliases come from `~/.zshrc`, which this host's interactive zsh loads; if your shell didn't (e.g. a non-interactive or other shell), run them as `zsh -ic '<function> && <command>'` so the env a function exports reaches the command
- This machine holds work GitHub access only: personal repositories and the personal `sdlc` registry are not reachable here, so personal SDLC work happens on personal machines
