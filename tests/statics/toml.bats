#!/usr/bin/env bats
# Every toml config parses, and the Noctalia config validates with its one allowed warning.
load ../helpers

# Noctalia's offline validator cannot load plugin manifests, so the plugin
# widget type is the one warning this config may produce. Any other warning or
# error is a real schema problem.
noctalia_config_ok() {
    output=$(noctalia config validate "$1" 2>&1) || { printf '%s\n' "$output"; return 1; }
    ! printf '%s\n' "$output" \
        | grep -vF 'widget.tailnet: unrecognized widget type "rylos/tailnet:bar"' \
        | grep -qE '^(ERROR|WARN)'
}

@test "every toml config parses" {
    python3 -c 'import tomllib' >/dev/null 2>&1 || skip "python3 tomllib missing"
    for cfg in "$dotfiles_root"/mise.toml "$dotfiles_root"/mise.*.toml "$dotfiles_root"/mise.*.lock \
            "$dotfiles_root"/global/*.toml "$dotfiles_root"/global/*.lock \
            "$dotfiles_root"/desktop/.config/aerospace/aerospace.toml \
            "$dotfiles_root"/desktop/.config/noctalia/config.toml \
            "$dotfiles_root"/home/.config/maki/*.toml \
            "$dotfiles_root"/home/.config/helix/*.toml; do
        [ -f "$cfg" ] || continue
        run python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$cfg"
        assert_success
    done
}

@test "the Noctalia config validates" {
    command -v noctalia >/dev/null 2>&1 \
        && noctalia config validate --help >/dev/null 2>&1 \
        || skip "noctalia with config validate not installed"
    run noctalia_config_ok "$dotfiles_root/desktop/.config/noctalia/config.toml"
    assert_success
}

@test "the Noctalia bar carries the Tailnet widget" {
    python3 -c 'import tomllib' >/dev/null 2>&1 || skip "python3 tomllib missing"
    run python3 -c '
import sys, tomllib
cfg = tomllib.load(open(sys.argv[1], "rb"))
assert cfg["plugins"]["enabled"] == ["rylos/tailnet"]
assert cfg["widget"]["tailnet"]["type"] == "rylos/tailnet:bar"
assert "tailnet" in cfg["bar"]["main"]["end"]
' "$dotfiles_root/desktop/.config/noctalia/config.toml"
    assert_success
}
