# set env vars
source ~/.config/fish/vars.fish

# set up plugins
source ~/.config/fish/fundle.fish

# Set up fuzzing directory changing
zoxide init fish --cmd n | source

# source extra local config
if test -d ~/.config/fish/extra
    source ~/.config/fish/extra/*.fish
end

# startup splashes
if status --is-interactive
    # include abbreviations
    source ~/.config/fish/abbreviations.fish

    # fetch sys info: https://github.com/willeccles/f
    f

    # set custom prompt
    set fish_greeting
end
