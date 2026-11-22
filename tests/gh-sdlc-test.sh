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
            printf 'DASH v4.26.3\n'
            exit 0
        fi
        printf '%s\n' "$*" >"$state/dash-args"
        env >"$state/dash-env"
        exit 0 ;;
    issue)
        cat "$state/issue-meta"
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
    "gh extension install dlvhdr/gh-dash --pin v4.26.3" "$out"
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

finish
