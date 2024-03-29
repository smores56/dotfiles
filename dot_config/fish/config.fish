# set env vars
source ~/.config/fish/vars.fish

# set up plugins
source ~/.config/fish/fundle.fish

# set up fuzzing directory changing
zoxide init fish --cmd c | source

# include abbreviations
source ~/.config/fish/abbreviations.fish

# startup splashes
if status --is-interactive
    # fetch sys info: https://github.com/willeccles/f
    f

    # set custom prompt
    set fish_greeting
    starship init fish | source
end
