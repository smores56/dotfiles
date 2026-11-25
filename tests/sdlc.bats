#!/usr/bin/env bats
# The sdlc CLI's unit tests. support.py resolves its imports from sdlc/tests,
# so `python3 -m unittest <module>` fails from the repo root; each module runs
# from that directory. The broker module takes ~15s on its own, so it is one
# test rather than one per case.
load helpers

setup() {
    command -v python3 >/dev/null 2>&1 || skip "python3 is not installed"
    cd "$dotfiles_root/sdlc/tests" || return 1
}

@test "the broker transport" {
    run python3 -m unittest test_broker_transport
    assert_success
}

@test "the issue CLI" {
    run python3 -m unittest test_sdlc_issues
    assert_success
}

@test "the skill modules" {
    run python3 -m unittest test_skills
    assert_success
}
