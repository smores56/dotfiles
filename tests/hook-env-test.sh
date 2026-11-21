#!/usr/bin/env bash
# Sourcing lib.sh must drop the git environment a hook exports, or a test
# that makes a fixture repo commits into the checkout that is being pushed.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

out=$(GIT_DIR=/nope GIT_WORK_TREE=/nope GIT_INDEX_FILE=/nope bash -c \
    '. "$1/tests/lib.sh"; printf "%s|%s|%s\n" "${GIT_DIR:-}" "${GIT_WORK_TREE:-}" "${GIT_INDEX_FILE:-}"' \
    sh "$root")
expect "sourcing lib.sh drops the hook's git environment" "||" "$out"

finish
