if not functions -q fundle
    eval (curl -sfL https://git.io/fundle-install)
end

fundle plugin 'jorgebucaran/autopair.fish'
fundle plugin franciscolourenco/done
fundle plugin joshmedeski/fish-lf-icons
fundle plugin pure-fish/pure
fundle plugin acomagu/fish-async-prompt

fundle init
