if not functions -q fundle
    eval (curl -sfL https://git.io/fundle-install)
end

fundle plugin 'jorgebucaran/hydro'
fundle plugin 'jorgebucaran/autopair.fish'
fundle plugin 'franciscolourenco/done'
fundle plugin 'PatrickF1/fzf.fish'
fundle plugin 'joshmedeski/fish-lf-icons'

fundle init