function set-wallpaper --description "Set the desktop background image"
    set wallpaper (ls ~/Pictures/wallpapers/* | gum choose --header="Pick a wallpaper")
    or return (error "Must choose a wallpaper")

    ln -sf "$wallpaper" ~/.wallpaper
    nohup qtile cmd-obj -o cmd -f reload_config > /dev/null &
end
