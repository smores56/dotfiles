#!/usr/bin/env bash
# zellij-tab-name: renames the caller's tab only when zellij still shows its
# default name, and only once that tab holds a second terminal pane.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

script=$root/home/.local/bin/zellij-tab-name
bin=$tmp/bin
doc=$tmp/panes.json
calls=$tmp/calls
mkdir -p "$bin"

# The fake reports the argument list it was called with, and answers the one
# query the script makes.
cat >"$bin/zellij" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$CALLS"
case $* in
    "action list-panes -t -j") cat "$PANES" ;;
esac
EOF
chmod +x "$bin/zellij"

# panes id:plugin:tab:name … lays out a list-panes document, pretty-printed the
# way zellij prints it: one field per line, one flat object per pane.
panes() {
    local spec first=1
    printf '[\n'
    for spec in "$@"; do
        IFS=: read -r id plugin tab name <<<"$spec"
        [ "$first" = 1 ] || printf ',\n'
        first=0
        printf '  {\n    "id": %s,\n    "is_plugin": %s,\n    "is_focused": false,\n    "title": "x",\n    "tab_id": %s,\n    "tab_position": %s,\n    "tab_name": "%s"\n  }' \
            "$id" "$plugin" "$tab" "$tab" "$name"
    done
    printf '\n]\n'
}

# run_ <pane id | -> [args…]: the script with a canned session, recording calls.
run_() {
    local pane=$1
    shift
    : >"$calls"
    if [ "$pane" = - ]; then
        env -i PATH="$bin:/usr/bin:/bin" HOME="$tmp/home" PANES="$doc" CALLS="$calls" \
            "$script" "$@" >/dev/null 2>&1
    else
        env -i PATH="$bin:/usr/bin:/bin" HOME="$tmp/home" PANES="$doc" CALLS="$calls" \
            ZELLIJ_PANE_ID="$pane" "$script" "$@" >/dev/null 2>&1
    fi
    made=$(paste -sd'|' - <"$calls")
}
listed="action list-panes -t -j"

panes '100:true:0:Tab #1' '7:false:0:Tab #1' '8:false:0:Tab #1' >"$doc"
run_ 7 '~/dotfiles'
expect "a split tab takes the folder name" \
    "$listed|action rename-tab --tab-id 0 ~/dotfiles" "$made"

panes '100:true:0:Tab #1' '7:false:0:Tab #1' >"$doc"
run_ 7 '~/dotfiles'
expect "a lone pane keeps following its own title" "$listed" "$made"

panes '100:true:0:~/dotfiles' '7:false:0:~/dotfiles' '8:false:0:~/dotfiles' >"$doc"
run_ 7 '~/elsewhere'
expect "a tab the person named is left alone" "$listed" "$made"

panes '100:true:0:my own tab' '7:false:0:my own tab' '8:false:0:my own tab' >"$doc"
run_ 7 '~/dotfiles'
expect "a spaced name the person chose is left alone" "$listed" "$made"

# One terminal here and one in the next tab: this tab still holds a lone pane.
panes '100:true:0:Tab #1' '7:false:0:Tab #1' '9:false:1:Tab #2' >"$doc"
run_ 7 '~/dotfiles'
expect "panes in another tab do not count" "$listed" "$made"

# A tab named "Tab #4" at position 3 is still the default name.
panes '100:true:3:Tab #4' '7:false:3:Tab #4' '8:false:3:Tab #4' >"$doc"
run_ 7 '~/dotfiles'
expect "the default name is recognised past the first tab" \
    "$listed|action rename-tab --tab-id 3 ~/dotfiles" "$made"

panes '100:true:0:Tab #1' '7:false:0:Tab #1' '8:false:0:Tab #1' >"$doc"
run_ 99 '~/dotfiles'
expect "an unknown pane names nothing" "$listed" "$made"

run_ - '~/dotfiles'
expect "outside zellij nothing runs" "" "$made"

panes '100:true:0:Tab #1' '7:false:0:Tab #1' '8:false:0:Tab #1' >"$doc"
run_ 7
expect "a name is required" "" "$made"

panes '100:true:0:Tab #1' '7:false:0:Tab #1' '8:false:0:Tab #1' >"$doc"
printf 'zellij: no session\n' >"$tmp/err"
cat >"$bin/zellij" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$CALLS"
exit 1
EOF
chmod +x "$bin/zellij"
run_ 7 '~/dotfiles'
expect "a failing zellij changes nothing" "action list-panes -t -j" "$made"

finish
