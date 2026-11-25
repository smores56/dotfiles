#!/usr/bin/env bats
# The Maki guards: the TinyFish lookup guard, the key handoff, and no exported
# provider key anywhere in home/.
load ../helpers

@test "the TinyFish guard runs on every tool call" {
    run grep -qF 'set_slot("tool.*.input"' "$dotfiles_root/home/.config/maki/init.lua"
    assert_success
}

@test "the TinyFish guard allows only search" {
    run grep -qF 'ctx.tool ~= "tinyfish__search"' "$dotfiles_root/home/.config/maki/init.lua"
    assert_success
}

@test "the maki wrapper hands the keys to the maki process" {
    run grep -qF 'TINYFISH_API_KEY=$tinyfish exec "$bin"' "$dotfiles_root/home/.local/bin/maki"
    assert_success
}

@test "no file exports a provider key" {
    run grep -rnE '^\s*export (NEURALWATT|TINYFISH)_API_KEY' "$dotfiles_root/home"
    assert_failure
}
