function tailscale-hosts --description "List all tailscale hosts"
    tailscale status --json | jq ".Peer | to_entries[] | .value.HostName" -r
end
