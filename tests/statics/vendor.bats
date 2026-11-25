#!/usr/bin/env bats
# The vendored screensaver matches its checksum, stays pinned on every desktop platform, and fits its pane.
load ../helpers

@test "the vendored cbonsai source matches its recorded checksum" {
    run sh -c \
        "if command -v sha256sum >/dev/null 2>&1; then sum=\$(sha256sum '$dotfiles_root/vendor/cbonsai/cbonsai.c'); \
            else sum=\$(shasum -a 256 '$dotfiles_root/vendor/cbonsai/cbonsai.c'); fi; \
            printf '%s\\n' \"\$sum\" | grep -q '^3d74a154447a14b93e3c7d868eea51c5ccb770d8454de8f3541d887e89eb2622 '"
    assert_success
}

@test "the cbonsai build lockfile pins both tools on every desktop platform" {
    python3 -c 'import tomllib' >/dev/null 2>&1 || skip "python3 tomllib missing"
    run python3 -c '
import sys, tomllib
tools = tomllib.load(open(sys.argv[1], "rb"))["tools"]
for name in ("zig", "conda:ncurses"):
    entries = tools[name]
    for platform in ("linux-x64", "linux-arm64", "macos-arm64"):
        assert any("platforms." + platform in entry for entry in entries), (name, platform)
' "$dotfiles_root/mise.build.lock"
    assert_success
}

@test "the screensaver life stays inside cbonsai's range" {
    run sh -c \
        "for size in '24 80' '40 120' '50 200' '8 20'; do set -- \$size; \
            life=\$('$dotfiles_root/home/.local/bin/screensavers' --life \$1 \$2); \
            [ \$life -ge 10 ] && [ \$life -le 200 ] || exit 1; \
        done"
    assert_success
}

@test "the screensaver tree fits its pane and re-renders on resize" {
    command -v cbonsai >/dev/null 2>&1 || skip "cbonsai not installed"
    run python3 "$dotfiles_root/tests/cbonsai-fit.py"
    assert_success
}
