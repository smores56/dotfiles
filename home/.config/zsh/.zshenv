# Every zsh, interactive or not: agents, launchd jobs, and editors run
# `zsh -c`. The environment is the POSIX file every shell shares; sh emulation
# gives it word splitting and empty globs.
emulate sh -c '. "${XDG_CONFIG_HOME:-$HOME/.config}/shell/env.sh"'
