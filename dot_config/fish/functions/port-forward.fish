function port-forward --description "Port forward through SSH server"
    if test (count $argv) -gt 0
        set SshLocation $argv[1]
    else
        return (error "Must specify where to port forward")
    end

    set InternalPort ( if test (count $argv) -gt 1; echo $argv[2]; else; echo 3000; end )
    set ExternalPort ( if test (count $argv) -gt 2; echo $argv[3]; else; echo 80; end )

    ssh -gfNR "$ExternalPort:127.0.0.1:$InternalPort" "$SshLocation"
end
