# zoxide replaces `cd` with `c`; keep the shell usable when the tool or its
# shim is absent (fresh machine, container before `mise install`).
if status is-interactive; and type -q zoxide
    zoxide init fish --cmd c | source
end
