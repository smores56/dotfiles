function zellij-picker --description "Pick a zellij session"
    if test (count $argv) -gt 0
        zellij attach $argv[1] 2>/dev/null; or zellij -s $argv[1]
    else if zellij list-sessions 2>/dev/null
        set session (zellij list-sessions | gum choose);
        or return (error "You must pick a session!")
        zellij attach "$session"
    else
        zellij -s main
    end
end
