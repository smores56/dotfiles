# Personal machines only. The route lives in ~/.ssh/smortress.conf (Cloudflare
# Access through the token wrapper), so `sm` is plain ssh; `-t zsh` is what the
# identity lane deploys on smortress.
(( $+functions[abbr] )) &&
  abbr add --session --quiet --force -- 'sm=ssh smortress -t zsh'
