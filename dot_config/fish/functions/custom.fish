function error --description "Print error to stderr"
    echo (tput setaf 1)"error: $argv"(tput sgr0) 1>&2
end

function tmux-smart --description "Intelligent tmux liaison"
    if test (count $argv) -eq 0
        set sessions (tmux ls -F "#{session_name}" 2>/dev/null)
        if test (count $sessions) -eq 0
            tmux new -s main
        else
            tmux attach
        end
   else if test (count $argv) -eq 1
        tmux attach -t $argv[1] 2>/dev/null; or tmux new -s $argv[1]
    else
        tmux $argv[2..-1]
    end
end

function ssh-tmux --description "SSH into a tmux session"
    if test (count $argv) -gt 0
        set SshLocation $argv[1]
    else
        error "Must specify where to port forward"
        return 1
    end

    if test "$TMUX" = ""
        ssh "$SshLocation" -t "DISPLAY=:0 SSH_CONNECTION=1 tmux-smart "(echo $argv[2..-1])
    else
        error "Don't SSH into tmux from tmux!"
        return 1
    end
end

function port-forward --description "Port forward through SSH server"
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
