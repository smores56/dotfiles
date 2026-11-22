#!/usr/bin/env bash
# The `gh sdlc` extension: it points gh-dash at the sdlc config, pins the
# registry/transport/shell the fixed keymap relies on, and guards the verbs.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

wrapper=$root/home/.local/bin/gh-sdlc
config=$root/home/.config/sdlc/gh-dash.yml
h=$tmp/home
bin=$tmp/bin
state=$tmp/state
mkdir -p "$h/.config/sdlc" "$bin" "$state"

# gh serves the version probe and the act label lookup; every call is recorded.
cat >"$bin/gh" <<'EOF'
#!/bin/sh
state=$FAKE_GH_STATE
printf '%s\n' "$*" >>"$state/calls"
case $1 in
    dash)
        if [ "${2:-}" = --version ]; then
            [ -e "$state/no-gh-dash" ] && exit 1
            if [ -e "$state/wrong-version" ]; then
                printf 'module version: v4.26.3\n'
            else
                printf 'module version: v4.11.0\n'
            fi
            exit 0
        fi
        printf '%s\n' "$*" >"$state/dash-args"
        env >"$state/dash-env"
        exit 0 ;;
    issue)
        cat "$state/issue-$3" 2>/dev/null || exit 1
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

run_env() {
    env -i HOME="$h" PATH="$bin:/usr/bin:/bin" XDG_CONFIG_HOME="$h/.config" \
        FAKE_GH_STATE="$state" FAKE_SDLC_EXIT="${FAKE_SDLC_EXIT:-0}" \
        "$wrapper" "$@"
}
run() { run_env "$@" </dev/null; }
run_input() { printf '%s\n' "$1" | run_env "${@:2}"; }
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

: >"$state/wrong-version"
assert_not "a newer gh-dash is refused" run
contains "the pin is enforced" "v4.11.0 is required" "$out"
rm -f "$state/wrong-version"

if command -v yq >/dev/null 2>&1; then
    assert "the config opens on the issues view" yq -e '.defaults.view == "issues"' "$config"
    assert "the registry is limited to a page" yq -e '.defaults.issuesLimit == 50' "$config"
    expect "the config has six sections" 6 "$(yq '.issuesSections | length' "$config" 2>/dev/null)"
    expect "every section names the registry" 6 \
        "$(yq '[.issuesSections[] | select(.filters | contains("repo:smores56/sdlc"))] | length' "$config" 2>/dev/null)"
    expect "the re-approval section watches its label" 1 \
        "$(yq '[.issuesSections[] | select(.filters | contains("label:status:needs-reapproval"))] | length' "$config" 2>/dev/null)"
else
    printf 'skip gh-dash config structure (yq not installed)\n'
fi

# --- act dispatcher: type and state guards, confirmations, exit codes ---------

meta 824 "OPEN type:feature status:approved"
meta 831 "OPEN status:todo"
meta 900 "CLOSED type:feature status:done"
meta 999 "OPEN enhancement"

clear_calls
assert "act status routes a feature" run act status 824 smores56/sdlc
expect "status keeps the issue number" "status 824" "$(sdlc_calls)"
contains "the guard reads the pinned registry" \
    "issue view 824 --repo smores56/sdlc --json labels,state" "$(cat "$state/calls")"

rm -f "$h/.config/sdlc/gh-dash.yml"
clear_calls
assert "act does not need the dashboard config" run act next 824 smores56/sdlc
expect "next still routes without a config" "next 824" "$(sdlc_calls)"
[ -f "$config" ] && cp "$config" "$h/.config/sdlc/gh-dash.yml"

clear_calls
assert "act next routes a feature" run act next 824 smores56/sdlc
expect "next keeps the issue number" "next 824" "$(sdlc_calls)"

clear_calls
assert "act review routes a feature" run act review 824 smores56/sdlc
expect "review keeps the issue number" "review 824" "$(sdlc_calls)"

clear_calls
assert "act approve routes a feature" run act approve 824 smores56/sdlc
expect "approve keeps the issue number" "approve 824" "$(sdlc_calls)"

clear_calls
assert "act complete needs a y" run_input y act complete 824 smores56/sdlc
expect "complete routes after confirmation" "complete 824" "$(sdlc_calls)"

clear_calls
assert "act complete treats n as a no-op" run_input n act complete 824 smores56/sdlc
expect "a rejected complete calls nothing" "" "$(sdlc_calls)"
contains "the no-op names the action" "not complete" "$out"

clear_calls
assert "act cancel needs a y" run_input y act cancel 824 smores56/sdlc
expect "cancel routes after confirmation" "cancel 824" "$(sdlc_calls)"

clear_calls
assert "act start routes a task" run act start 831 smores56/sdlc
expect "start uses the task command" "task start 831" "$(sdlc_calls)"

clear_calls
assert "act finish needs a y" run_input y act finish 831 smores56/sdlc
expect "finish uses the task command" "task done 831" "$(sdlc_calls)"

clear_calls
assert "act abandon needs a y" run_input y act abandon 831 smores56/sdlc
expect "abandon uses the task command" "task cancel 831" "$(sdlc_calls)"

clear_calls
assert_not "a row from another repo is refused" run act status 824 smores56/dotfiles
contains "the repo refusal names the registry" "expected smores56/sdlc" "$out"
expect "a refused repo calls nothing" "" "$(sdlc_calls)"

clear_calls
assert_not "a missing repo is refused" run act status 824
contains "the missing repo names the registry" "expected smores56/sdlc" "$out"

assert_not "a non-numeric issue is refused" run act status '824;id' smores56/sdlc
contains "the number refusal names the value" "expected an issue number" "$out"
assert_not "a flag-like issue is refused" run act status -1 smores56/sdlc
assert_not "a range is refused" run act status 8-24 smores56/sdlc

clear_calls
assert_not "a feature verb refuses a task" run act status 831 smores56/sdlc
contains "the task refusal names the feature marker" "not a feature" "$out"
expect "a refused feature verb calls nothing" "" "$(sdlc_calls)"

clear_calls
assert_not "a task verb refuses a feature" run act start 824 smores56/sdlc
contains "the feature refusal names the task marker" "not a task" "$out"
expect "a refused task verb calls nothing" "" "$(sdlc_calls)"

assert_not "a closed issue is refused" run act status 900 smores56/sdlc
contains "the closed refusal names the state" "CLOSED" "$out"

assert_not "an unlabeled issue is not a task" run act start 999 smores56/sdlc
contains "the task refusal names the status marker" "status:" "$out"

assert_not "an unknown verb is refused" run act explode 824 smores56/sdlc
contains "the unknown verb is named" "unknown action: explode" "$out"

rm -f "$state/issue-824"
assert_not "missing issue metadata fails" run act status 824 smores56/sdlc
contains "the read failure names the issue" "cannot read #824" "$out"
meta 824 "OPEN type:feature status:approved"

clear_calls
FAKE_SDLC_EXIT=7 run act status 824 smores56/sdlc >/dev/null 2>&1
expect "the action's exit code propagates" 7 $?

# --- fixed keymap -------------------------------------------------------------

if command -v yq >/dev/null 2>&1; then
    expect "the keymap has nine verbs" 9 "$(yq '.keybindings.issues | length' "$config" 2>/dev/null)"
    expect "the verbs are the expected keys" \
        "$(printf '%s\n' S N v V x D t d ctrl+x | sort | tr '\n' ' ')" \
        "$(yq -r '.keybindings.issues[].key' "$config" | sort | tr '\n' ' ')"
    expect "every verb calls gh sdlc act" 9 \
        "$(yq '[.keybindings.issues[] | select(.command | contains("gh sdlc act"))] | length' "$config" 2>/dev/null)"
    expect "templates are IssueNumber and RepoName" "{{.IssueNumber}} {{.RepoName}} " \
        "$(yq -r '.keybindings.issues[].command' "$config" | grep -oE '\{\{[^}]+\}\}' | sort -u | tr '\n' ' ')"

    defaults="up down k j g G home end p o r R ctrl+d ctrl+u h l left right / y Y ? q esc ctrl+c a A c x X s"
    collisions=$(for key in $(yq -r '.keybindings.issues[].key' "$config"); do
        case " $defaults " in *" $key "*) printf '%s ' "$key" ;; esac
    done | tr -s ' ')
    expect "only x overrides a default key" "x " "$collisions"

    bad=0
    while IFS= read -r snippet; do
        snippet=${snippet//\{\{.IssueNumber\}\}/1}
        snippet=${snippet//\{\{.RepoName\}\}/smores56\/sdlc}
        sh -n -c "$snippet" 2>/dev/null || bad=1
    done < <(yq -r '.keybindings.issues[].command' "$config")
    expect "every snippet parses as sh" 0 "$bad"
else
    printf 'skip gh-dash keymap structure (yq not installed)\n'
fi

finish
