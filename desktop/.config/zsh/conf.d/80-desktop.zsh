# smorespro only: mise deploys this file under a Linux variant. `ct` is gtrash's
# "delete all" form without its confirmation prompt; gtrash itself is a desktop tool because macOS has no trash CLI.
# nym-vpnc is a system package from the image, not a mise tool, so its
# abbreviations appear only once the tool is installed.
(( $+functions[abbr] )) || return 0
() {
  local -A abbrs=()
  (( $+commands[gtrash] )) && abbrs[ct]='gtrash find --rm --force'
  if (( $+commands[nym-vpnc] )); then
    abbrs[nv]='sudo nym-vpnc'
    abbrs[nvc]='sudo nym-vpnc connect --wait'
    abbrs[nvd]='sudo nym-vpnc disconnect --wait'
  fi
  local name
  for name in ${(k)abbrs}; do
    abbr add --session --quiet --force -- "$name=${abbrs[$name]}" >/dev/null 2>&1
  done
}
