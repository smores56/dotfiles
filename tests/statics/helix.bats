#!/usr/bin/env bats
# helix: every configured language server is a pinned tool, and every
# language-servers entry names one that is defined.
load ../helpers

@test "every Helix language server is defined and pinned in global/config.toml" {
    helix_languages=$dotfiles_root/home/.config/helix/languages.toml
    helix_servers=$(grep -oE '^\[language-server\.[a-z-]+' "$helix_languages" \
        | sed 's/.*\.//' | LC_ALL=C sort -u)
    helix_missing=""
    for server in $helix_servers; do
        case $server in
            ruff) pkg='aqua:astral-sh/ruff' ;;
            taplo) pkg='aqua:tamasfe/taplo' ;;
            marksman) pkg='aqua:artempyanykh/marksman' ;;
            markdown-oxide) pkg='github:Feel-ix-343/markdown-oxide' ;;
            basedpyright) pkg='pipx:basedpyright' ;;
            *) helix_missing="$helix_missing $server(no pin)"; continue ;;
        esac
        grep -qF "\"$pkg\" = " "$dotfiles_root/global/config.toml" || helix_missing="$helix_missing $server($pkg)"
    done
    for server in $(grep -E '^language-servers' "$helix_languages" \
            | sed -E 's/.*\[//; s/\].*//; s/[" ]//g' | tr ',' '\n'); do
        printf '%s\n' "$helix_servers" | grep -qx "$server" || helix_missing="$helix_missing $server(undefined)"
    done
    assert_equal "$helix_missing" ""
}
