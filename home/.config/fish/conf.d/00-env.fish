# The environment is the POSIX file every shell shares, so fish sees what zsh,
# bash and agents' `zsh -c` see: sh sources it and fish copies what it exports.
for kv in (/bin/sh -c '. "$1" && env -0' sh ~/.config/shell/env.sh | string split0)
    set -l kv (string split -m1 = -- $kv)
    contains -- $kv[1] PWD OLDPWD SHLVL _; and continue
    set -gx $kv[1] $kv[2]
end
