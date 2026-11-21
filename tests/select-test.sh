#!/usr/bin/env bash
# tests/select.sh maps a changed-file list to the tests that cover it.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

select_tests() { printf '%s\n' "$@" | sh "$root/tests/select.sh"; }
selects() {  # selects <description> <expected> <paths...>
    local desc=$1 want=$2
    shift 2
    expect "$desc" "$want" "$(select_tests "$@")"
}

selects "documentation selects no behavioural tests" "" "README.md" "docs/loop.md"
selects "a fish config change selects the fish test" "fish-test.sh" \
    "home/.config/fish/conf.d/20-abbreviations.fish"
selects "a work shell change selects the fish test" "fish-test.sh" \
    "work/.config/shell/env.d/work.sh"
selects "a maki config change selects the maki test" "maki-test.sh" \
    "home/.config/maki/init.lua"
selects "a sops config change selects the sops tests" \
    "sops-age-key-test.sh sops-age-key-contract-test.sh" "home/.config/sops/sops.yaml"
selects "a selector change selects everything" "all" "tests/select.sh"
selects "an unknown path selects everything" "all" "brand/new/thing"
selects "repeated paths select one test" "maki-test.sh" \
    "home/.config/maki/init.lua" "home/.config/maki/permissions.toml"
selects "a source change selects its own test" "bootstrap-script-test.sh" \
    "scripts/bootstrap.sh"

finish
