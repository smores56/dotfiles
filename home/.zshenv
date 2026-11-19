# Every zsh, interactive or not (agents, launchd jobs, editors run `zsh -c`),
# reads the environment every shell shares; sh emulation gives the POSIX file
# its word splitting and empty globs, and a missing file (a pull before the
# apply links it) leaves zsh running without it. Interactive shells are fish;
# on the work Mac an interactive zsh still reads the employer's ~/.zshrc.
emulate sh -c 'f=${XDG_CONFIG_HOME:-$HOME/.config}/shell/env.sh; [ -r "$f" ] && . "$f"; unset f'
