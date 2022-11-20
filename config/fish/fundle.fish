if not functions -q fundle
    eval (curl -sfL https://git.io/fundle-install)
end

fundle plugin 'IlanCosman/tide@v5'
fundle plugin 'jorgebucaran/autopair.fish'
fundle plugin 'franciscolourenco/done'
fundle plugin 'joshmedeski/fish-lf-icons'

fundle init