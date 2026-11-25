#!/usr/bin/env bash
# zellij-tab-name: renames the caller's tab only when zellij still shows its
# default name, and only once that tab holds a second tiled pane.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

script=$root/home/.local/bin/zellij-tab-name
bin=$tmp/bin
doc=$tmp/panes.json
calls=$tmp/calls
mkdir -p "$bin"

# One argument per line, so an argument that was split or unquoted shows up.
cat >"$bin/zellij" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >>"$CALLS"
case $* in
    "action list-panes -t -j") cat "$PANES" ;;
esac
EOF
chmod +x "$bin/zellij"

# panes id:plugin:floating:tab:name … lays out a list-panes document shaped like
# zellij 0.46 prints it: one field per line, a nested status block that carries
# an "id" of its own, and a pane title that is not the tab name.
panes() {
    local spec first=1
    printf '[\n'
    for spec in "$@"; do
        IFS=: read -r id plugin floating tab name <<<"$spec"
        [ "$first" = 1 ] || printf ',\n'
        first=0
        printf '  {\n    "id": %s,\n    "is_plugin": %s,\n    "is_focused": false,\n    "is_floating": %s,\n    "is_suppressed": false,\n    "title": "/some/place",\n    "program_status": [\n      {\n        "id": null,\n        "text": "working"\n      }\n    ],\n    "tab_id": %s,\n    "tab_position": 0,\n    "tab_name": "%s"\n  }' \
            "$id" "$plugin" "$floating" "$tab" "$name"
    done
    printf '\n]\n'
}

# run_ <pane id | -> [args…]: the script against a canned session.
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
listed="action|list-panes|-t|-j"
# The name fish passes is prompt_pwd's, which abbreviates home with a tilde
# that must reach zellij as typed.
# shellcheck disable=SC2088
folder='~/dotfiles'
# shellcheck disable=SC2088
other='~/elsewhere'

panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' '8:false:false:0:Tab #1' >"$doc"
run_ 7 "$folder"
expect "a split tab takes the folder name" \
    "$listed|action|rename-tab|--tab-id|0|--|$folder" "$made"

panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' >"$doc"
run_ 7 "$folder"
expect "a lone pane keeps following its own title" "$listed" "$made"

panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' '8:false:true:0:Tab #1' >"$doc"
run_ 7 "$folder"
expect "a floating pane is not a split" "$listed" "$made"

panes '100:true:false:0:/home/x/dotfiles' '7:false:false:0:/home/x/dotfiles' '8:false:false:0:/home/x/dotfiles' >"$doc"
run_ 7 "$other"
expect "a tab the person named is left alone" "$listed" "$made"

panes '100:true:false:0:my own tab' '7:false:false:0:my own tab' '8:false:false:0:my own tab' >"$doc"
run_ 7 "$folder"
expect "a spaced name the person chose is left alone" "$listed" "$made"

# One tiled pane here and one in the next tab: this tab still holds a lone pane.
panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' '9:false:false:1:Tab #2' >"$doc"
run_ 7 "$folder"
expect "panes in another tab do not count" "$listed" "$made"

# zellij names an unrenamed tab after its id, not its position.
panes '100:true:false:3:Tab #4' '7:false:false:3:Tab #4' '8:false:false:3:Tab #4' >"$doc"
run_ 7 "$folder"
expect "the default name is recognised past the first tab" \
    "$listed|action|rename-tab|--tab-id|3|--|$folder" "$made"

panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' '8:false:false:0:Tab #1' >"$doc"
run_ 99 "$folder"
expect "an unknown pane names nothing" "$listed" "$made"

panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' '8:false:false:0:Tab #1' >"$doc"
run_ 7 '-rf'
expect "a name is never read as one of zellij's options" \
    "$listed|action|rename-tab|--tab-id|0|--|-rf" "$made"

run_ - "$folder"
expect "outside zellij nothing runs" "" "$made"

run_ 7
expect "a name is required" "" "$made"

cat >"$bin/zellij" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >>"$CALLS"
exit 1
EOF
chmod +x "$bin/zellij"
run_ 7 "$folder"
expect "a failing zellij changes nothing" "$listed" "$made"

finish
