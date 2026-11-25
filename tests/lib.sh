# shellcheck shell=sh
# Sourced by the hook-env test. A git hook exports GIT_DIR and friends, and a
# test that makes a fixture repository would otherwise commit into the checkout
# that is being pushed; tests/helpers.bash unsets the same set for bats.

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_NAMESPACE \
    GIT_PREFIX GIT_QUARANTINE_PATH
