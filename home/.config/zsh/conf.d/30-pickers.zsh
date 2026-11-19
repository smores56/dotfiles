# Television pickers. Cancelling a picker prints nothing, and every jump
# helper treats an empty pick as a no-op.
_jump() {  # _jump <path>: zoxide's c when it is loaded, plain cd otherwise
  [[ -n ${1-} ]] || return
  if (( $+functions[c] )); then
    zoxide add -- "$1" 2>/dev/null
    c "$1"
  else
    cd -- "$1"
  fi
}

r() {  # pick a checkout; a bare repo has none, so pick one of its worktrees
  local p w
  p=$(tv repos) || return
  [[ -n $p ]] || return
  if [[ $(git -C "$p" rev-parse --is-bare-repository 2>/dev/null) == true ]]; then
    w=$(cd -- "$p" && tv worktrees) || return
    [[ -n $w ]] || return
    p=$w
  fi
  _jump "$p"
}

w() {  # pick a worktree of the current repository
  local p
  p=$(tv worktrees) && _jump "$p"
}
ef() { local f; f=$(tv files) && [[ -n $f ]] && hx "$f" }
et() { local f; f=$(tv text) && [[ -n $f ]] && hx "$f" }
ms() { local s; s=$(tv maki-sessions) && [[ -n $s ]] && maki-session-resume "$s" }
