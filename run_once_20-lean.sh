#!/bin/sh

ELAN_SCRIPT_URL=https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh

curl "$ELAN_SCRIPT_URL" -sSf | \
  sh -s - --no-modify-path --default-toolchain leanprover/lean4:nightly -y