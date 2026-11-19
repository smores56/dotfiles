# Linux desktops: abbreviations for tools only they have.
status is-interactive; or return

command -q gtrash; and abbr -a ct gtrash find --rm --force
if command -q nym-vpnc
    abbr -a nv sudo nym-vpnc
    abbr -a nvc sudo nym-vpnc connect --wait
    abbr -a nvd sudo nym-vpnc disconnect --wait
end
