#!/bin/sh
# Runs one behavioural test by name: tests/run-one.sh fish
set -eu
name=${1:?usage: tests/run-one.sh <name>}
dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ -f "$dir/$name.bats" ]; then
    exec bats "$dir/$name.bats"
fi
script=$dir/"$name-test.sh"
[ -f "$script" ] || { printf 'run-one: no test named %s\n' "$name" >&2; exit 2; }
exec bash "$script"
