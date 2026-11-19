# The environment is the POSIX file every shell shares, so fish sees what zsh,
# bash and agents' `zsh -c` see: sh sources it and fish copies what it exports.
# The file unsets ZDOTDIR, which an import cannot express, so fish drops it too.
set -e ZDOTDIR
for kv in (/bin/sh -c '. "$1" && env -0' sh ~/.config/shell/env.sh 2>/dev/null | string split0)
    set -l kv (string split -m1 = -- $kv)
    # Names fish cannot hold (exported bash functions, a.b) stay with sh.
    string match -qr '^[A-Za-z_][A-Za-z0-9_]*$' -- $kv[1]; or continue
    contains -- $kv[1] PWD OLDPWD SHLVL _; and continue
    set -gx $kv[1] $kv[2]
end
