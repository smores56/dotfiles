function error --description "Print error to stderr"
    echo (tput setaf 1)"error: $argv"(tput sgr0) 1>&2
end

function dotfiles --description "Manage my dotfiles"
    git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME $argv
end

function ssh_tmux --description "SSH into a TMUX session"
    if test (count $argv) -gt 0
        set SshLocation $argv[1]
    else
        error "Must specify where to port forward"
        return 1
    end

    if test "$TMUX" = ""
        ssh "$SshLocation" -t "tmux a 2>/dev/null || tmux new -s main; exit"
    else
        error "Don't SSH into tmux from tmux!"
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
