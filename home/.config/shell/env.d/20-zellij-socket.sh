# The zellij web server (#954) runs as a system unit under smortress's uid and
# has to list the sessions an SSH login creates, so both must resolve one IPC
# directory. Zellij would otherwise use $XDG_RUNTIME_DIR/zellij, which the unit
# cannot reach; /run/zellij is the fixed path the unit creates for itself.
# Exported only where that directory exists, so laptops keep the runtime
# default, and only when nothing already chose a directory for this shell.
if [ -z "${ZELLIJ_SOCKET_DIR-}" ] && [ -d /run/zellij ]; then
    ZELLIJ_SOCKET_DIR=/run/zellij
    export ZELLIJ_SOCKET_DIR
fi
