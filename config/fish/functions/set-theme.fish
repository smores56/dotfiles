function set-theme --description "Set the system theme to light or dark"
    if test $argv[1] != light; and test $argv[1] != dark
        return (error "Must set theme to either `light` or `dark`")
    end

    set -U THEME $argv[1]
    
    # Select a new theme from those available
    if test "$argv[2]" = "--select"    
        # Use `gum` to pick a theme from the alacritty theme pool
        set newTheme (ls -1 "$HOME/.config/alacritty/$THEME/" | cut --fields=1 --delimiter=. | gum choose)
        if test -z "$newTheme"
            return (error "Must pick one of the available $THEME themes.")
        end

        # Set the appropriate THEME variable
        if test "$THEME" = "light"
            set -U LIGHT_THEME "$newTheme"
        else
            set -U DARK_THEME "$newTheme"
        end
    else
        # Set a LIGHT_THEME default
        if test -z "$LIGHT_THEME"
            set -U LIGHT_THEME rose_pine_dawn
        end
        
        # Set a DARK_THEME default
        if test -z "$DARK_THEME"
            set -U DARK_THEME rose_pine_moon
        end
    end

    # Pick theme from light and dark
    if test "$THEME" = "light"
        set -U themeName "$LIGHT_THEME"
    else
        set -U themeName "$DARK_THEME"
    end

    # Set light/dark lazygit theme
    cp -sf "$HOME/.config/lazygit/$THEME-config.yml" ~/.config/lazygit/config.yml
    
    # Set Alacritty theme
    cp -sf "$HOME/.config/alacritty/$THEME/$themeName.yml" ~/.config/alacritty/theme.yml
    
    # Set Helix theme
    mkdir -p ~/.config/helix/themes
    cp -sf "/lib/helix/runtime/themes/$themeName.toml" ~/.config/helix/themes/theme.toml
end
