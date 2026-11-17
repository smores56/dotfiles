# Personal machines only. Tailscale resolves the node and checks its host key,
# so this needs no ~/.ssh entry; `-t` is handed to the system ssh, and zsh is
# the shell the identity lane deploys on smortress.
(( $+functions[abbr] )) &&
  abbr add --session --quiet --force -- 'sm=tailscale ssh smortress -t zsh'
