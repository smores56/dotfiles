#!/usr/bin/env bats
# The `gh sdlc` extension: it points gh-dash at the sdlc config, pins the
# registry/transport/shell the fixed keymap relies on, and guards the verbs.
load helpers

setup() {
    wrapper=$dotfiles_root/home/.local/bin/gh-sdlc
    config=$dotfiles_root/home/.config/sdlc/gh-dash.yml
    h=$BATS_TEST_TMPDIR/home
    bin=$BATS_TEST_TMPDIR/bin
    state=$BATS_TEST_TMPDIR/state
    mkdir -p "$h/.config/sdlc" "$bin" "$state"
    cp "$config" "$h/.config/sdlc/gh-dash.yml"

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
                printf 'gh-dash version dev\nmodule version: v4.26.3\n'
            else
                printf 'gh-dash version v4.26.3-sdlc\n'
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

    cat >"$bin/sdlc" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$FAKE_GH_STATE/sdlc-calls"
exit "${FAKE_SDLC_EXIT:-0}"
EOF
    chmod +x "$bin/gh" "$bin/sdlc"
}

# An emptied environment keeps the host's PATH, HOME, and SDLC_* out of the test.
sdlc_env() {
    env -i HOME="$h" PATH="$bin:/usr/bin:/bin" XDG_CONFIG_HOME="$h/.config" \
        FAKE_GH_STATE="$state" FAKE_SDLC_EXIT="${FAKE_SDLC_EXIT:-0}" \
        "$wrapper" "$@"
}

# No tty: an act that confirmed nothing must not block on the wait prompt.
gh_sdlc() { sdlc_env "$@" </dev/null; }
gh_sdlc_input() { printf '%s\n' "$1" | sdlc_env "${@:2}"; }

meta() { printf '%s\n' "$2" >"$state/issue-$1"; }
clear_calls() { rm -f "$state/sdlc-calls"; }
sdlc_calls() { cat "$state/sdlc-calls" 2>/dev/null || true; }
need_yq() { command -v yq >/dev/null 2>&1 || skip 'yq not installed'; }

# The wait only runs with a tty, which /dev/null and pipes do not provide.
pty_wait_prompt() {
    python3 - "$wrapper" "$bin" "$state" "$h" <<'PY'
import os, pty, select, sys, time, fcntl, termios, struct
wrapper, bin_dir, state, home = sys.argv[1:5]
env = {
    "HOME": home,
    "PATH": bin_dir + ":/usr/bin:/bin",
    "XDG_CONFIG_HOME": home + "/.config",
    "FAKE_GH_STATE": state,
    "FAKE_SDLC_EXIT": "0",
}
pid, fd = pty.fork()
if pid == 0:
    os.execve(wrapper, [wrapper, "act", "status", "824", "smores56/sdlc"], env)
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 100, 0, 0))
out = b""
sent = False
deadline = time.time() + 10
reaped = False
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.1)
    if r:
        try:
            data = os.read(fd, 65536)
        except OSError:
            data = b""
        if data:
            out += data
    if b"Press Enter to return" in out and not sent:
        os.write(fd, b"\r")
        sent = True
    done, status = os.waitpid(pid, os.WNOHANG)
    if done:
        reaped = True
        break
if not reaped:
    os.kill(pid, 9)
    os.waitpid(pid, 0)
    print("pty: wrapper did not exit")
    sys.exit(1)
text = out.decode("utf-8", "replace")
if "Press Enter to return" not in text:
    print("pty: missing wait prompt")
    sys.exit(1)
if os.waitstatus_to_exitcode(status) != 0:
    print("pty: exit", os.waitstatus_to_exitcode(status))
    sys.exit(1)
PY
}

@test "the gh sdlc wrapper is executable" {
    run test -x "$wrapper"
    assert_success
}

@test "gh sdlc launches gh-dash" {
    run gh_sdlc
    assert_success
}

@test "gh-dash receives the sdlc config" {
    run gh_sdlc
    assert_success
    assert_equal "$(cat "$state/dash-args" 2>/dev/null)" \
        "dash --config $h/.config/sdlc/gh-dash.yml"
}

# The config's section filters name this repo, so the wrapper decides the
# registry and the transport instead of inheriting a work environment's.
@test "the registry is pinned" {
    run gh_sdlc
    assert_success
    run grep -F -- 'SDLC_REPO=smores56/sdlc' "$state/dash-env"
    assert_success
}

@test "the transport is pinned to gh" {
    run gh_sdlc
    assert_success
    run grep -F -- 'SDLC_TRANSPORT=gh' "$state/dash-env"
    assert_success
}

# SHELL=/bin/sh is what makes the fixed keymap snippets POSIX.
@test "the custom-command shell is POSIX" {
    run gh_sdlc
    assert_success
    run grep -F -- 'SHELL=/bin/sh' "$state/dash-env"
    assert_success
}

@test "update notices stay out of the dashboard" {
    run gh_sdlc
    assert_success
    run grep -F -- 'GH_NO_UPDATE_NOTIFIER=1' "$state/dash-env"
    assert_success
}

@test "a missing config fails" {
    rm "$h/.config/sdlc/gh-dash.yml"
    run --separate-stderr gh_sdlc
    assert_failure
    assert_stderr --partial 'config not found'
}

@test "SDLC_GH_DASH_CONFIG overrides the config path" {
    alt=$BATS_TEST_TMPDIR/alt.yml
    cp "$config" "$alt"
    run env -i HOME="$h" PATH="$bin:/usr/bin:/bin" XDG_CONFIG_HOME="$h/.config" \
        FAKE_GH_STATE="$state" SDLC_GH_DASH_CONFIG="$alt" "$wrapper"
    assert_success
    assert_equal "$(cat "$state/dash-args")" "dash --config $alt"
}

@test "a missing gh-dash fails" {
    : >"$state/no-gh-dash"
    run -127 --separate-stderr gh_sdlc
    assert_failure 127
    assert_stderr --partial 'smores56 fork'
}

@test "a newer gh-dash is refused" {
    : >"$state/wrong-version"
    run -127 --separate-stderr gh_sdlc
    assert_failure 127
    assert_stderr --partial 'fork build is required'
}

# --- gh-dash config structure -------------------------------------------------

@test "the config opens on the issues view" {
    need_yq
    run yq -e '.defaults.view == "issues"' "$config"
    assert_success
}

@test "the registry is limited to a page" {
    need_yq
    run yq -e '.defaults.issuesLimit == 50' "$config"
    assert_success
}

@test "the table hides the repo column" {
    need_yq
    run yq -e '.defaults.layout.issues.repo.hidden == true' "$config"
    assert_success
}

@test "the table hides the creator column" {
    need_yq
    run yq -e '.defaults.layout.issues.creator.hidden == true' "$config"
    assert_success
}

@test "the table hides the state column" {
    need_yq
    run yq -e '.defaults.layout.issues.state.hidden == true' "$config"
    assert_success
}

@test "the config has six sections" {
    need_yq
    assert_equal "$(yq '.issuesSections | length' "$config" 2>/dev/null)" 6
}

@test "the PR view is empty" {
    need_yq
    assert_equal "$(yq '.prSections | length' "$config" 2>/dev/null)" 0
}

@test "every section names the registry" {
    need_yq
    assert_equal "$(yq '[.issuesSections[] | select(.filters | contains("repo:smores56/sdlc"))] | length' "$config" 2>/dev/null)" 6
}

@test "the re-approval section watches its label" {
    need_yq
    assert_equal "$(yq '[.issuesSections[] | select(.filters | contains("label:status:needs-reapproval"))] | length' "$config" 2>/dev/null)" 1
}

# --- act dispatcher: type and state guards, confirmations, exit codes ---------

@test "act status routes a feature" {
    meta 824 "OPEN type:feature status:approved"
    clear_calls
    run gh_sdlc act status 824 smores56/sdlc
    assert_success
    assert_equal "$(sdlc_calls)" "status 824"
    # No tty here, so the action must not print the wait prompt.
    refute_output --partial 'Press Enter'
    # The guard reads the labels of the pinned registry, not of the row's repo.
    run grep -F -- 'issue view 824 --repo smores56/sdlc --json labels,state' "$state/calls"
    assert_success
}

@test "act does not need the dashboard config" {
    meta 824 "OPEN type:feature status:approved"
    rm "$h/.config/sdlc/gh-dash.yml"
    clear_calls
    run gh_sdlc act next 824 smores56/sdlc
    assert_success
    assert_equal "$(sdlc_calls)" "next 824"
}

@test "act next routes a feature" {
    meta 824 "OPEN type:feature status:approved"
    clear_calls
    run gh_sdlc act next 824 smores56/sdlc
    assert_success
    assert_equal "$(sdlc_calls)" "next 824"
}

@test "act review routes a feature" {
    meta 824 "OPEN type:feature status:approved"
    clear_calls
    run gh_sdlc act review 824 smores56/sdlc
    assert_success
    assert_equal "$(sdlc_calls)" "review 824"
}

@test "act approve routes a feature" {
    meta 824 "OPEN type:feature status:approved"
    clear_calls
    run gh_sdlc act approve 824 smores56/sdlc
    assert_success
    assert_equal "$(sdlc_calls)" "approve 824"
}

@test "act complete needs a y" {
    meta 824 "OPEN type:feature status:approved"
    clear_calls
    run gh_sdlc_input y act complete 824 smores56/sdlc
    assert_success
    assert_equal "$(sdlc_calls)" "complete 824"
}

@test "act complete treats n as a no-op" {
    meta 824 "OPEN type:feature status:approved"
    clear_calls
    run --separate-stderr gh_sdlc_input n act complete 824 smores56/sdlc
    assert_success
    assert_equal "$(sdlc_calls)" ""
    assert_stderr --partial 'not complete'
}

@test "act cancel needs a y" {
    meta 824 "OPEN type:feature status:approved"
    clear_calls
    run gh_sdlc_input y act cancel 824 smores56/sdlc
    assert_success
    assert_equal "$(sdlc_calls)" "cancel 824"
}

@test "act start routes a task" {
    meta 831 "OPEN status:todo"
    clear_calls
    run gh_sdlc act start 831 smores56/sdlc
    assert_success
    assert_equal "$(sdlc_calls)" "task start 831"
}

@test "act finish needs a y" {
    meta 831 "OPEN status:todo"
    clear_calls
    run gh_sdlc_input y act finish 831 smores56/sdlc
    assert_success
    assert_equal "$(sdlc_calls)" "task done 831"
}

@test "act abandon needs a y" {
    meta 831 "OPEN status:todo"
    clear_calls
    run gh_sdlc_input y act abandon 831 smores56/sdlc
    assert_success
    assert_equal "$(sdlc_calls)" "task cancel 831"
}

@test "a row from another repo is refused" {
    meta 824 "OPEN type:feature status:approved"
    clear_calls
    run --separate-stderr gh_sdlc act status 824 smores56/dotfiles
    assert_failure
    assert_stderr --partial 'expected smores56/sdlc'
    assert_equal "$(sdlc_calls)" ""
}

@test "a missing repo is refused" {
    meta 824 "OPEN type:feature status:approved"
    run --separate-stderr gh_sdlc act status 824
    assert_failure
    assert_stderr --partial 'expected smores56/sdlc'
}

@test "a non-numeric issue is refused" {
    run --separate-stderr gh_sdlc act status '824;id' smores56/sdlc
    assert_failure
    assert_stderr --partial 'expected an issue number'
}

@test "a flag-like issue is refused" {
    run gh_sdlc act status -1 smores56/sdlc
    assert_failure
}

@test "a range is refused" {
    run gh_sdlc act status 8-24 smores56/sdlc
    assert_failure
}

@test "a feature verb refuses a task" {
    meta 831 "OPEN status:todo"
    clear_calls
    run --separate-stderr gh_sdlc act status 831 smores56/sdlc
    assert_failure
    assert_stderr --partial 'not a feature'
    assert_equal "$(sdlc_calls)" ""
}

@test "a task verb refuses a feature" {
    meta 824 "OPEN type:feature status:approved"
    clear_calls
    run --separate-stderr gh_sdlc act start 824 smores56/sdlc
    assert_failure
    assert_stderr --partial 'not a task'
    assert_equal "$(sdlc_calls)" ""
}

@test "a closed issue is refused" {
    meta 900 "CLOSED type:feature status:done"
    run --separate-stderr gh_sdlc act status 900 smores56/sdlc
    assert_failure
    assert_stderr --partial 'CLOSED'
}

@test "an unlabeled issue is not a task" {
    meta 999 "OPEN enhancement"
    run --separate-stderr gh_sdlc act start 999 smores56/sdlc
    assert_failure
    assert_stderr --partial 'status:'
}

@test "an unknown verb is refused" {
    meta 824 "OPEN type:feature status:approved"
    run --separate-stderr gh_sdlc act explode 824 smores56/sdlc
    assert_failure
    assert_stderr --partial 'unknown action: explode'
}

@test "missing issue metadata fails" {
    rm -f "$state/issue-824"
    run --separate-stderr gh_sdlc act status 824 smores56/sdlc
    assert_failure
    assert_stderr --partial 'cannot read #824'
}

@test "empty issue metadata fails" {
    : >"$state/issue-824"
    run --separate-stderr gh_sdlc act status 824 smores56/sdlc
    assert_failure
    assert_stderr --partial 'cannot read #824'
}

@test "the action's exit code propagates" {
    meta 824 "OPEN type:feature status:approved"
    FAKE_SDLC_EXIT=7 run -7 gh_sdlc act status 824 smores56/sdlc
    assert_equal "$status" 7
}

@test "the wait runs on a tty" {
    meta 824 "OPEN type:feature status:approved"
    run pty_wait_prompt
    assert_success
}

# --- fixed keymap -------------------------------------------------------------

@test "the keymap has nine verbs" {
    need_yq
    assert_equal "$(yq '.keybindings.issues | length' "$config" 2>/dev/null)" 9
}

@test "the verbs are the expected keys" {
    need_yq
    assert_equal \
        "$(yq -r '.keybindings.issues[].key' "$config" | sort | tr '\n' ' ')" \
        "$(printf '%s\n' S N v V x D T d ctrl+x | sort | tr '\n' ' ')"
}

@test "every verb calls gh sdlc act" {
    need_yq
    assert_equal "$(yq '[.keybindings.issues[] | select(.command | contains("gh sdlc act"))] | length' "$config" 2>/dev/null)" 9
}

@test "every verb has a help name" {
    need_yq
    assert_equal "$(yq '[.keybindings.issues[] | select(.name != "")] | length' "$config" 2>/dev/null)" 9
}

@test "templates are IssueNumber and RepoName" {
    need_yq
    assert_equal \
        "$(yq -r '.keybindings.issues[].command' "$config" | grep -oE '\{\{[^}]+\}\}' | sort -u | tr '\n' ' ')" \
        "{{.IssueNumber}} {{.RepoName}} "
}

@test "only x overrides a default key" {
    need_yq
    defaults="up down k j g G home end p P o r R ctrl+s / y Y ctrl+d ctrl+u h l left right ? q esc ctrl+c L a A c C x X t s"
    collisions=$(for key in $(yq -r '.keybindings.issues[].key' "$config"); do
        case " $defaults " in *" $key "*) printf '%s ' "$key" ;; esac
    done | tr -s ' ')
    assert_equal "$collisions" "x "
}

@test "every snippet parses as sh" {
    need_yq
    bad=0
    while IFS= read -r snippet; do
        snippet=${snippet//\{\{.IssueNumber\}\}/1}
        snippet=${snippet//\{\{.RepoName\}\}/smores56\/sdlc}
        sh -n -c "$snippet" 2>/dev/null || bad=1
    done < <(yq -r '.keybindings.issues[].command' "$config")
    assert_equal "$bad" 0
}
