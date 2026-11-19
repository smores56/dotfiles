# Every zsh, interactive or not (agents, launchd jobs, editors run `zsh -c`),
# reads the environment every shell shares; sh emulation gives the POSIX file
# its word splitting and empty globs. Interactive shells are fish; on the work
# Mac an interactive zsh still reads the employer's ~/.zshrc on its own.
emulate sh -c '. "${XDG_CONFIG_HOME:-$HOME/.config}/shell/env.sh"'
