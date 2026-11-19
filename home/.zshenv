# Every zsh, agents' `zsh -c` included, reads the shared environment. sh
# emulation gives the POSIX file its word splitting and empty globs; a missing
# file (a pull before the apply links it) leaves zsh running without it.
emulate sh -c 'f=${XDG_CONFIG_HOME:-$HOME/.config}/shell/env.sh; [ -r "$f" ] && . "$f"; unset f'
