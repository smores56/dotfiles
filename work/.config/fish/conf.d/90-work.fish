# smoreswork. The employer's ~/.zshrc sets up pyenv, nvm and gcloud and takes
# about a second to source, so fish adds their directories statically instead,
# right after the mise shims so a mise tool still wins as it does in zsh.
set -l shims (contains -i -- $HOME/.local/share/mise/shims $PATH)
# nvm's default is lts/*: the newest installed release.
set -l nodes ~/.nvm/versions/node/v*
set -l node
set -q nodes[1]; and set node (printf '%s\n' $nodes | sort -V | tail -1)/bin
set -l extra
for dir in (path filter -d ~/.pyenv/shims $node /opt/homebrew/share/google-cloud-sdk/bin)
    contains -- $dir $PATH; or set -a extra $dir
end
if set -q shims[1]; and set -q extra[1]
    set -gx PATH $PATH[1..$shims] $extra $PATH[(math $shims + 1)..]
end
# Same socket as work/.config/shell/env.d/work.sh: the LaunchAgent's agent is
# what smortress's pam_rssh asks for a touch, and fish must not start without it.
if test -S "$HOME/.local/state/ssh/agent.sock"
    set -gx SSH_AUTH_SOCK "$HOME/.local/state/ssh/agent.sock"
end
set -gx SSH_SK_PROVIDER /usr/lib/ssh-keychain.dylib
set -gx OP_BIOMETRIC_UNLOCK_ENABLED true
test -d ~/.pyenv; and set -gx PYENV_ROOT ~/.pyenv
test -d ~/.nvm; and set -gx NVM_DIR ~/.nvm

status is-interactive; or return

abbr -a a claude
# Work checkouts are flat hand clones in ~/Blitzy, worktrees under .worktrees/.
abbr -a r 'path dirname ~/Blitzy/*/.git ~/Blitzy/*/.worktrees/*/.git | fzf | read f; and c $f'

# blitzy-dev ships its helpers (set-dev, rdb_dev, ddb, ...) as zsh functions
# that export into the calling shell. Each gets a fish wrapper that runs it in
# zsh and copies back only the variables it changed.
set -q BLITZY_ENV_FUNCTIONS; or set -g BLITZY_ENV_FUNCTIONS ~/blitzy_env_functions.sh
test -f $BLITZY_ENV_FUNCTIONS; or return

# Sourcing the file resets _BLITZY_CURRENT_ENV_FILE and BLITZY_ENV, so they are
# restored, and the first is exported, or switching envs would never unset the
# previous env's variables.
set -g __blitzy_zsh_script '
out=$1 file=$2; shift 2
saved_file=$_BLITZY_CURRENT_ENV_FILE saved_env=$BLITZY_ENV
source $file
_BLITZY_CURRENT_ENV_FILE=$saved_file BLITZY_ENV=$saved_env
export _BLITZY_CURRENT_ENV_FILE
typeset -A before
for k in ${(k)parameters[(R)*export*]}; do before[$k]=${(P)k}; done
eval "${(j: :)${(q-)@}}"
rc=$?
{
  for k in ${(k)parameters[(R)*export*]}; do
    [[ ${+before[$k]} == 1 && ${before[$k]} == ${(P)k} ]] || print -rN -- S $k ${(P)k}
  done
  for k in ${(k)before}; do
    [[ ${parameters[$k]} == *export* ]] || print -rN -- U $k
  done
} >$out
exit $rc
'

function __blitzy_zsh --description 'Run a blitzy-dev zsh helper and import its env changes'
    set -l out (mktemp); or return
    zsh -c $__blitzy_zsh_script blitzy $out $BLITZY_ENV_FUNCTIONS $argv
    set -l rc $status
    set -l recs (string split0 <$out)
    rm -f $out
    set -l i 1
    while test $i -le (count $recs)
        switch $recs[$i]
            case S
                set -l k $recs[(math $i + 1)]
                contains -- $k PWD OLDPWD SHLVL _; or set -gx $k $recs[(math $i + 2)]
                set i (math $i + 3)
            case U
                set -eg $recs[(math $i + 1)]
                set i (math $i + 2)
            case '*'
                set i (math $i + 1)
        end
    end
    return $rc
end

for name in (zsh -c 'b=(${(k)functions} ${(k)aliases}); source $1 >/dev/null; a=(${(k)functions} ${(k)aliases}); print -l ${a:|b}' _ $BLITZY_ENV_FUNCTIONS)
    string match -q '_*' -- $name; and continue
    function $name --inherit-variable name
        __blitzy_zsh $name $argv
    end
end
