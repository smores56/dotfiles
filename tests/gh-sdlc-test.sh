#!/usr/bin/env bash
# The `gh sdlc` extension: it points gh-dash at the sdlc config and pins the
# registry/transport/shell the fixed keymap relies on.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

wrapper=$root/home/.local/bin/gh-sdlc
config=$root/home/.config/sdlc/gh-dash.yml
h=$tmp/home
bin=$tmp/bin
state=$tmp/state
mkdir -p "$h/.config/sdlc" "$bin" "$state"

# gh serves the launch probe and the act label lookup; every call is recorded.
cat >"$bin/gh" <<'EOF'
#!/bin/sh
state=$FAKE_GH_STATE
printf '%s\n' "$*" >>"$state/calls"
case $1 in
    dash)
        if [ "${2:-}" = --version ]; then
            [ -e "$state/no-gh-dash" ] && exit 1
            printf 'DASH v4.11.0\n'
            exit 0
        fi
        printf '%s\n' "$*" >"$state/dash-args"
        env >"$state/dash-env"
        exit 0 ;;
    issue)
        cat "$state/issue-$3" 2>/dev/null
        exit 0 ;;
esac
exit 1
EOF
chmod +x "$bin/gh"

cat >"$bin/sdlc" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_GH_STATE/sdlc-calls"
exit "${FAKE_SDLC_EXIT:-0}"
EOF
chmod +x "$bin/sdlc"

run() {
    env -i HOME="$h" PATH="$bin:/usr/bin:/bin" XDG_CONFIG_HOME="$h/.config" \
        FAKE_GH_STATE="$state" FAKE_SDLC_EXIT="${FAKE_SDLC_EXIT:-0}" \
        "$wrapper" "$@"
}
run_input() { printf '%s\n' "$1" | run "${@:2}"; }
meta() { printf '%s\n' "$2" >"$state/issue-$1"; }
clear_calls() { rm -f "$state/sdlc-calls"; }
sdlc_calls() { cat "$state/sdlc-calls" 2>/dev/null; }

assert "the gh sdlc wrapper is executable" test -x "$wrapper"
[ -f "$config" ] && cp "$config" "$h/.config/sdlc/gh-dash.yml"

assert "gh sdlc launches gh-dash" run
expect "gh-dash receives the sdlc config" \
    "dash --config $h/.config/sdlc/gh-dash.yml" "$(cat "$state/dash-args" 2>/dev/null)"
contains "the registry is pinned" "SDLC_REPO=smores56/sdlc" "$(cat "$state/dash-env" 2>/dev/null)"
contains "the transport is pinned to gh" "SDLC_TRANSPORT=gh" "$(cat "$state/dash-env" 2>/dev/null)"
contains "the custom-command shell is POSIX" "SHELL=/bin/sh" "$(cat "$state/dash-env" 2>/dev/null)"
contains "update notices stay out of the dashboard" "GH_NO_UPDATE_NOTIFIER=1" \
    "$(cat "$state/dash-env" 2>/dev/null)"

rm -f "$h/.config/sdlc/gh-dash.yml"
assert_not "a missing config fails" run
contains "the missing config is named" "config not found" "$out"
[ -f "$config" ] && cp "$config" "$h/.config/sdlc/gh-dash.yml"

alt=$tmp/alt.yml
[ -f "$config" ] && cp "$config" "$alt"
assert "SDLC_GH_DASH_CONFIG overrides the config path" \
    env -i HOME="$h" PATH="$bin:/usr/bin:/bin" XDG_CONFIG_HOME="$h/.config" \
        FAKE_GH_STATE="$state" SDLC_GH_DASH_CONFIG="$alt" "$wrapper"
expect "the override reaches gh-dash" "dash --config $alt" "$(cat "$state/dash-args")"

: >"$state/no-gh-dash"
assert_not "a missing gh-dash fails" run
contains "the install command is named" \
    "gh extension install dlvhdr/gh-dash --pin v4.11.0" "$out"
rm -f "$state/no-gh-dash"

if command -v yq >/dev/null 2>&1; then
    assert "the config opens on the issues view" yq -e '.defaults.view == "issues"' "$config"
    assert "the registry is limited to a page" yq -e '.defaults.issuesLimit == 50' "$config"
    expect "the config has five sections" 5 "$(yq '.issuesSections | length' "$config" 2>/dev/null)"
    expect "every section names the registry" 5 \
        "$(yq '[.issuesSections[] | select(.filters | contains("repo:smores56/sdlc"))] | length' "$config" 2>/dev/null)"
    expect "every section is issues-only" 5 \
        "$(yq '[.issuesSections[] | select(.filters | contains("is:issue"))] | length' "$config" 2>/dev/null)"
else
    printf 'skip gh-dash config structure (yq not installed)\n'
fi

# --- act dispatcher: type and state guards, confirmations, exit codes ---------

meta 824 "OPEN type:feature status:approved"
meta 831 "OPEN status:todo"
meta 900 "CLOSED type:feature status:done"
meta 999 "OPEN enhancement"

clear_calls
assert "act status routes a feature" run act status 824
expect "status keeps the issue number" "status 824" "$(sdlc_calls)"

rm -f "$h/.config/sdlc/gh-dash.yml"
clear_calls
assert "act does not need the dashboard config" run act next 824
expect "next still routes without a config" "next 824" "$(sdlc_calls)"
[ -f "$config" ] && cp "$config" "$h/.config/sdlc/gh-dash.yml"

clear_calls
assert "act next routes a feature" run act next 824
expect "next keeps the issue number" "next 824" "$(sdlc_calls)"

clear_calls
assert "act review routes a feature" run act review 824
expect "review keeps the issue number" "review 824" "$(sdlc_calls)"

clear_calls
assert "act approve routes a feature" run act approve 824
expect "approve keeps the issue number" "approve 824" "$(sdlc_calls)"

clear_calls
assert "act complete needs a y" run_input y act complete 824
expect "complete routes after confirmation" "complete 824" "$(sdlc_calls)"

clear_calls
assert_not "act complete rejects n" run_input n act complete 824
expect "a rejected complete calls nothing" "" "$(sdlc_calls)"
contains "the refusal names the action" "not complete" "$out"

clear_calls
assert "act cancel needs a y" run_input y act cancel 824
expect "cancel routes after confirmation" "cancel 824" "$(sdlc_calls)"

clear_calls
assert "act start routes a task" run act start 831
expect "start uses the task command" "task start 831" "$(sdlc_calls)"

clear_calls
assert "act finish needs a y" run_input y act finish 831
expect "finish uses the task command" "task done 831" "$(sdlc_calls)"

clear_calls
assert "act abandon needs a y" run_input y act abandon 831
expect "abandon uses the task command" "task cancel 831" "$(sdlc_calls)"

clear_calls
assert_not "a feature verb refuses a task" run act status 831
contains "the task refusal names the feature marker" "not a feature" "$out"
expect "a refused feature verb calls nothing" "" "$(sdlc_calls)"

clear_calls
assert_not "a task verb refuses a feature" run act start 824
contains "the feature refusal names the task marker" "not a task" "$out"
expect "a refused task verb calls nothing" "" "$(sdlc_calls)"

assert_not "a closed issue is refused" run act status 900
contains "the closed refusal names the state" "CLOSED" "$out"

assert_not "an unlabeled issue is not a task" run act start 999
contains "the task refusal names the status marker" "status:" "$out"

assert_not "an unknown verb is refused" run act explode 824
contains "the unknown verb is named" "unknown action: explode" "$out"

rm -f "$state/issue-824"
assert_not "missing issue metadata fails" run act status 824
meta 824 "OPEN type:feature status:approved"

clear_calls
FAKE_SDLC_EXIT=7 run act status 824 >/dev/null 2>&1
expect "the action's exit code propagates" 7 $?

# --- fixed keymap -------------------------------------------------------------

if command -v yq >/dev/null 2>&1; then
    expect "the keymap has nine verbs" 9 "$(yq '.keybindings.issues | length' "$config" 2>/dev/null)"
    expect "the verbs are the expected keys" \
        "$(printf '%s\n' S N v V x D t d ctrl+x | sort | tr '\n' ' ')" \
        "$(yq -r '.keybindings.issues[].key' "$config" | sort | tr '\n' ' ')"
    expect "every verb calls gh sdlc act" 9 \
        "$(yq '[.keybindings.issues[] | select(.command | contains("gh sdlc act"))] | length' "$config" 2>/dev/null)"
    expect "every snippet keeps its exit code" 9 \
        "$(yq -r '.keybindings.issues[].command' "$config" | grep -F 'rc=$?' | grep -cF 'exit $rc')"
    expect "every snippet uses only IssueNumber" 0 \
        "$(yq -r '.keybindings.issues[].command' "$config" | grep -oE '\{\{[^}]+\}\}' | grep -vc '^{{.IssueNumber}}$')"

    defaults="up down k j g G h l p P o r R / y Y ctrl+s ? q L a A c C x X t s"
    collisions=$(for key in $(yq -r '.keybindings.issues[].key' "$config"); do
        case " $defaults " in *" $key "*) printf '%s ' "$key" ;; esac
    done | tr -s ' ')
    expect "only x and t override defaults" "x t " "$collisions"

    bad=0
    while IFS= read -r snippet; do
        sh -n -c "${snippet//\{\{.IssueNumber\}\}/1}" 2>/dev/null || bad=1
    done < <(yq -r '.keybindings.issues[].command' "$config")
    expect "every snippet parses as sh" 0 "$bad"
else
    printf 'skip gh-dash keymap structure (yq not installed)\n'
fi

finish
