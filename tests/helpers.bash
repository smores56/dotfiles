# shellcheck shell=bash
# Sourced by every .bats file: the checkout fixtures are built around, the
# pinned assertion libraries, and the git hook environment.
# `load` may hand over a bare name, so fall back to the test's own dir.
helpers_dir=$(dirname -- "${BASH_SOURCE[0]}")
case $helpers_dir in /*) ;; *) helpers_dir=$BATS_TEST_DIRNAME ;; esac
dotfiles_root=$(CDPATH='' cd -- "$helpers_dir/.." && pwd -P)

# bats searches only $BATS_LIB_PATH, which defaults to /usr/lib/bats: no root
# here, and the same path on macOS. scripts/install-bats-libs.sh fills it.
export BATS_LIB_PATH=${BATS_LIB_PATH:+$BATS_LIB_PATH:}${XDG_DATA_HOME:-$HOME/.local/share}/bats
bats_load_library bats-support
bats_load_library bats-assert

# A git hook exports GIT_DIR and friends; a test that makes a fixture
# repository would otherwise commit into the invoking checkout.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE \
    GIT_PREFIX GIT_QUARANTINE_PATH

# run --separate-stderr is load-bearing: assert_silent checks both streams.
bats_require_minimum_version 1.5.0
