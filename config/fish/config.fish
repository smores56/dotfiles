# set env vars
source ~/.config/fish/vars.fish

# set up plugins
source ~/.config/fish/fundle.fish

# Set up fuzzing directory changing
zoxide init fish --cmd n | source

# include abbreviations
source ~/.config/fish/abbreviations.fish

# source extra local config
for f in ~/.config/fish/extra/**/*.fish
    source $f
end

# set custom prompt
set fish_greeting

# startup splashes
if status --is-interactive
    # fetch sys info: https://github.com/willeccles/f
    f

    # set custom prompt
    set fish_greeting
    starship init fish | source
end
