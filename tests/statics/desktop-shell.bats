#!/usr/bin/env bats
# Every flatpak id is reverse-DNS, kitty and zellij start fish, the layouts hold, and no config calls exec().
load ../helpers

@test "every flatpak id looks like a reverse-DNS app id" {
    run sh -c \
        "sed -n 's/^\"flatpak-user:\([^\"]*\)\".*/\1/p' '$dotfiles_root/mise.desktop.toml' \
            | grep -vE '^[A-Za-z0-9_]+(\.[A-Za-z0-9_-]+)+\$'"
    assert_failure
}

@test "kitty starts fish through its mise shim" {
    for kitty_conf in "$dotfiles_root"/desktop/.config/kitty/linux.conf \
            "$dotfiles_root"/desktop/.config/kitty/macos.conf; do
        run grep -qxF 'shell ${HOME}/.local/share/mise/shims/fish' "$kitty_conf"
        assert_success
    done
}

@test "zellij starts fish" {
    run grep -qx 'default_shell "fish"' "$dotfiles_root/home/.config/zellij/config.kdl"
    assert_success
}

@test "kitty terminfo is installed where ncurses looks" {
    run test -f "$dotfiles_root/home/.terminfo/x/xterm-kitty"
    assert_success
}

@test "the focus layout centers a 120-column pane" {
    run grep -qE '^[[:space:]]*pane size=120 focus=true$' \
        "$dotfiles_root/home/.config/zellij/layouts/focus.kdl"
    assert_success
}

@test "the focus layout runs the screensaver in both gutters" {
    run sh -c "[ \$(grep -c 'command \"screensavers\"' \
        '$dotfiles_root/home/.config/zellij/layouts/focus.kdl') -eq 2 ]"
    assert_success
}

@test "the screensaver abbreviation is added" {
    run grep -qx 'abbr -a sv screensavers' \
        "$dotfiles_root/home/.config/fish/conf.d/20-abbreviations.fish"
    assert_success
}

@test "zsh has no interactive config: no ZDOTDIR, zim, plugins, or conda zsh" {
    run sh -c "[ -e '$dotfiles_root/home/.config/zsh' ] || grep -rnE 'zim|zsh-plugins|conda:zsh|ZDOTDIR' \
        '$dotfiles_root/mise.toml' '$dotfiles_root'/mise.*.toml \
        '$dotfiles_root/global/config.toml' '$dotfiles_root/scripts'"
    assert_failure
}

@test "maki/pin.env pins version, target, and checksum" {
    run sh -c \
        "grep -qE '^MAKI_VERSION=v[0-9]+\.[0-9]+\.[0-9]+\$' '$dotfiles_root/maki/pin.env' \
            && grep -qE '^MAKI_SHA256=[0-9a-f]{64}\$' '$dotfiles_root/maki/pin.env' \
            && grep -qE '^MAKI_TARGET=[A-Za-z0-9_-]+\$' '$dotfiles_root/maki/pin.env'"
    assert_success
}

# `mise dot status` renders templates and hooks, so an exec() there would run.
@test "no template or hook calls exec()" {
    run grep -rnE 'exec\(' "$dotfiles_root"/identity "$dotfiles_root"/desktop "$dotfiles_root"/home \
        "$dotfiles_root"/mise.toml "$dotfiles_root"/mise.*.toml
    assert_failure
}

# `--config-dir global` links ~/.config/mise to global/; a copy under home/ would drift.
@test "the global mise config lives only in global/" {
    run test -e "$dotfiles_root/home/.config/mise"
    assert_failure
}
