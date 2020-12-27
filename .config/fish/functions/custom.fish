function error --description "Print error to stderr"
    echo (tput setaf 1)"error: $argv"(tput sgr0) 1>&2
end

function dotfiles --description "Manage my dotfiles"
    git --work-tree=$HOME $argv
end

function ssh_tab --description "SSH into a `tab` session"
    if test (count $argv) -gt 0
        set SshLocation $argv[1]
    else
        error "Must specify where to port forward"
        return 1
    end

    if test "$TAB" = ""
        ssh "$SshLocation" -t "SSH_CONNECTION=1 tab; exit"
    else
        error "Don't SSH into tab from tab!"
        return 1
    end
end

function port_forward --description "Port forward through SSH server"
    if test (count $argv) -gt 0
        set SshLocation $argv[1]
    else
        error "Must specify where to port forward"
        return 1
    end

    set InternalPort ( if test (count $argv) -gt 1; echo $argv[2]; else; echo 3000; end )
    set ExternalPort ( if test (count $argv) -gt 2; echo $argv[3]; else; echo 80; end )

    ssh -gfNR "$ExternalPort:127.0.0.1:$InternalPort" "$SshLocation"
end

function set_theme --description "Set theming for apps based on the time of day"
    if test (count $argv) -gt 0
        if test $argv[1] = "light"; or test $argv[1] = "dark"
            set -xg THEME $argv[1]
        else
            error "Only 'light' and 'dark' themes are supported"
            return 1
        end
    else
        set currentTime (date '+%H')
        if test $currentTime -ge '7'; and test $currentTime -lt '18'
            set -xg THEME light
        else
            set -xg THEME dark
        end
    end
    
    if test $THEME = "light"
        set -xg BAT_THEME gruvbox-light
        ln -f ~/.config/alacritty/light.yml ~/.config/alacritty/alacritty.yml
        ln -f ~/.config/amp/light.yml ~/.config/amp/config.yml
    else
        set -xg BAT_THEME gruvbox
        ln -f ~/.config/alacritty/dark.yml ~/.config/alacritty/alacritty.yml
        ln -f ~/.config/amp/dark.yml ~/.config/amp/config.yml
    end
end
