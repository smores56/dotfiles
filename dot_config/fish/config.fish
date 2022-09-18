# set env vars
source ~/.config/fish/vars.fish

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
    zoxide init fish --cmd c | source
    starship init fish | source
end

# Run Sway unless off of the default tty
if test -z "$DISPLAY"; and test "/dev/tty1" = (tty)
    dbus-run-session sway
end
