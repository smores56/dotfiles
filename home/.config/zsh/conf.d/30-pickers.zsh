# Television pickers. Cancelling a picker prints nothing: `cd ""` is a no-op,
# and the editor functions skip an empty pick.
alias r='cd "$(tv repos)"'
alias w='cd "$(tv worktrees)"'
ef() { local f; f=$(tv files) && [[ -n $f ]] && hx "$f" }
et() { local f; f=$(tv text) && [[ -n $f ]] && hx "$f" }
