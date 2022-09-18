function zellij-picker --description "Pick a zellij session"
    if test (count $argv) -gt 0
        zellij attach $argv[1] 2>/dev/null; or zellij -s $argv[1]
    else if zellij list-sessions 2>/dev/null
        zellij attach (zellij list-sessions | gum choose)
    else
        zellij -s main
    end
end
