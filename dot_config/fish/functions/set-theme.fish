function set-theme --description "Set the system theme"
    argparse --min-args=1 s/select -- $argv
    or return

    set theme $argv[1]
    if test "$theme" != light -a "$theme" != dark
        return (error "theme must be `light` or `dark`")
    end

    if test -z "$_flag_select"
        if test $theme = light
            set variant rose_pine_dawn
        else
            set variant rose_pine_moon
        end
    else
        set variants (ls ~/.config/alacritty/"$theme"/*.yml | xargs basename -a -s .yml)
        set variant (gum choose --header="Pick a $theme theme" $variants)
        or return (error "Must pick a variant")
    end

    mkdir -p ~/.config/helix/themes/
    ln -sf ~/.config/lazygit/"$theme-config.yml" ~/.config/lazygit/config.yml
    ln -sf ~/.config/alacritty/"$theme/$variant.toml" ~/.config/alacritty/theme.yml
    ln -sf ~/.config/alacritty/"$theme/$variant.toml" ~/.theme.yml

    if test (uname) = Darwin
        ln -sf /opt/homebrew/opt/helix/libexec/runtime/themes/"$variant.toml" ~/.config/helix/themes/theme.toml
    else
        ln -sf /lib/helix/runtime/themes/"$variant.toml" ~/.config/helix/themes/theme.toml
    end
end
