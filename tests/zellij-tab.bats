#!/usr/bin/env bats
# zellij-tab-name: renames the caller's tab only when zellij still shows its
# default name, and only once that tab holds a second tiled pane.
load helpers

setup() {
    script=$dotfiles_root/home/.local/bin/zellij-tab-name
    bin=$BATS_TEST_TMPDIR/bin
    doc=$BATS_TEST_TMPDIR/panes.json
    calls=$BATS_TEST_TMPDIR/calls
    mkdir -p "$bin" "$BATS_TEST_TMPDIR/home"
    # One argument per line, so an argument that was split or unquoted shows up.
    cat >"$bin/zellij" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >>"$CALLS"
case $* in
    "action list-panes -t -j") cat "$PANES" ;;
esac
EOF
    chmod +x "$bin/zellij"
}

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

# run_ <pane id | -> [args…]: the script against a canned session, leaving the
# zellij argv (one argument per line, joined by |) in $made.
run_() {
    local pane=$1
    shift
    : >"$calls"
    if [ "$pane" = - ]; then
        env -i PATH="$bin:/usr/bin:/bin" HOME="$BATS_TEST_TMPDIR/home" \
            PANES="$doc" CALLS="$calls" "$script" "$@" >/dev/null 2>&1
    else
        env -i PATH="$bin:/usr/bin:/bin" HOME="$BATS_TEST_TMPDIR/home" \
            PANES="$doc" CALLS="$calls" ZELLIJ_PANE_ID="$pane" "$script" "$@" >/dev/null 2>&1
    fi
    made=$(paste -sd'|' - <"$calls")
}

listed="action|list-panes|-t|-j"
# The name fish passes is prompt_pwd's, which abbreviates home with a tilde that
# must reach zellij as typed.
folder='~/dotfiles'
other='~/elsewhere'

@test "a split tab takes the folder name" {
    panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' '8:false:false:0:Tab #1' >"$doc"
    run_ 7 "$folder"
    assert_equal "$made" "$listed|action|rename-tab|--tab-id|0|--|$folder"
}

@test "a lone pane keeps following its own title" {
    panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' >"$doc"
    run_ 7 "$folder"
    assert_equal "$made" "$listed"
}

@test "a floating pane is not a split" {
    panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' '8:false:true:0:Tab #1' >"$doc"
    run_ 7 "$folder"
    assert_equal "$made" "$listed"
}

@test "a tab the person named is left alone" {
    panes '100:true:false:0:/home/x/dotfiles' '7:false:false:0:/home/x/dotfiles' \
        '8:false:false:0:/home/x/dotfiles' >"$doc"
    run_ 7 "$other"
    assert_equal "$made" "$listed"
}

@test "a spaced name the person chose is left alone" {
    panes '100:true:false:0:my own tab' '7:false:false:0:my own tab' '8:false:false:0:my own tab' >"$doc"
    run_ 7 "$folder"
    assert_equal "$made" "$listed"
}

# One tiled pane here and one in the next tab: this tab still holds a lone pane.
@test "panes in another tab do not count" {
    panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' '9:false:false:1:Tab #2' >"$doc"
    run_ 7 "$folder"
    assert_equal "$made" "$listed"
}

# zellij names an unrenamed tab after its id, not its position.
@test "the default name is recognised past the first tab" {
    panes '100:true:false:3:Tab #4' '7:false:false:3:Tab #4' '8:false:false:3:Tab #4' >"$doc"
    run_ 7 "$folder"
    assert_equal "$made" "$listed|action|rename-tab|--tab-id|3|--|$folder"
}

@test "an unknown pane names nothing" {
    panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' '8:false:false:0:Tab #1' >"$doc"
    run_ 99 "$folder"
    assert_equal "$made" "$listed"
}

@test "a name is never read as one of zellij's options" {
    panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' '8:false:false:0:Tab #1' >"$doc"
    run_ 7 '-rf'
    assert_equal "$made" "$listed|action|rename-tab|--tab-id|0|--|-rf"
}

@test "outside zellij nothing runs" {
    panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' '8:false:false:0:Tab #1' >"$doc"
    run_ - "$folder"
    assert_equal "$made" ""
}

@test "a name is required" {
    panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' '8:false:false:0:Tab #1' >"$doc"
    run_ 7
    assert_equal "$made" ""
}

@test "a failing zellij changes nothing" {
    cat >"$bin/zellij" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >>"$CALLS"
exit 1
EOF
    chmod +x "$bin/zellij"
    panes '100:true:false:0:Tab #1' '7:false:false:0:Tab #1' '8:false:false:0:Tab #1' >"$doc"
    run_ 7 "$folder"
    assert_equal "$made" "$listed"
}
