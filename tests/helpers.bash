# shellcheck shell=bash
# Sourced by every .bats file: the checkout fixtures are built around, the
# pinned assertion libraries, and the git hook environment.

# `load` may hand over a bare name, so fall back to the test's own dir.
helpers_dir=$(dirname -- "${BASH_SOURCE[0]}")
case $helpers_dir in /*) ;; *) helpers_dir=$BATS_TEST_DIRNAME ;; esac
# shellcheck disable=SC2034 # the suites read it
dotfiles_root=$(CDPATH='' cd -- "$helpers_dir/.." && pwd -P)

# bats searches only $BATS_LIB_PATH, which defaults to /usr/lib/bats: no root
# here, and the same path on macOS. scripts/install-bats-libs.sh fills it.
# Assigned, never appended: an inherited entry could shadow the pinned library.
BATS_LIB_PATH=${XDG_DATA_HOME:-$HOME/.local/share}/bats
export BATS_LIB_PATH
bats_load_library bats-support
bats_load_library bats-assert

# run --separate-stderr is load-bearing: assert_silent checks both streams.
bats_require_minimum_version 1.5.0
assert_silent() {
    # shellcheck disable=SC2154 # bats sets both from the last `run`
    assert_equal "$output$stderr" ""
}

# A git hook exports GIT_DIR and friends; a test that makes a fixture
# repository would otherwise commit into the invoking checkout.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE \
    GIT_PREFIX GIT_QUARANTINE_PATH
