function set-wallpaper --description "Set the desktop background image"
    set wallpaper (ls ~/Pictures/wallpapers/* | gum choose --header="Pick a wallpaper")
    or return (error "Must choose a wallpaper")

    ln -sf "$wallpaper" ~/.wallpaper
    gum spin sleep 1 &
    nohup 2>/dev/null qtile cmd-obj -o cmd -f reload_config &
    wait gum
end
