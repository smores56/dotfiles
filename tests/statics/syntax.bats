#!/usr/bin/env bats
# Every shell script in the tree parses, along with the zsh, fish, and python entry points.
load ../helpers

# A mise shim whose version is unset is on PATH but fails at exec. Treating it
# as installed turns one environment gap into a pile of misleading failures.
usable_shell() {  # usable_shell <shell>: print its path when it runs
    local bin
    bin=$(command -v "$1" 2>/dev/null) || return 1
    "$bin" -c ':' >/dev/null 2>&1 || return 1
    printf '%s\n' "$bin"
}

shell_scripts() {
    for script in "$dotfiles_root"/home/.config/shell/env.sh "$dotfiles_root"/work/.config/shell/env.d/*.sh \
            "$dotfiles_root"/home/.local/bin/* "$dotfiles_root"/desktop/.local/bin/* \
            "$dotfiles_root"/scripts/*.sh "$dotfiles_root"/tests/*.sh "$dotfiles_root"/tests/*.bash \
            "$dotfiles_root"/.githooks/*; do
        [ -f "$script" ] || continue
        case $(head -n 1 "$script") in
            *python*) ;;
            *bash*) printf 'bash %s\n' "$script" ;;
            *) printf 'sh %s\n' "$script" ;;
        esac
    done
}

@test "every shell script parses" {
    while read -r dialect script; do
        run "$dialect" -n "$script"
        assert_success
    done < <(shell_scripts)
}

@test "syntax home/.zshenv (zsh)" {
    zsh_bin=$(usable_shell zsh) || skip "zsh not installed"
    run "$zsh_bin" -n "$dotfiles_root/home/.zshenv"
    assert_success
}

@test "every fish file parses (fish)" {
    fish_bin=$(usable_shell fish) || skip "fish not installed"
    for fish_file in "$dotfiles_root"/home/.config/fish/*.fish \
            "$dotfiles_root"/*/.config/fish/conf.d/*.fish "$dotfiles_root"/*/.config/fish/conf.d/*.fish.tera; do
        [ -f "$fish_file" ] || continue
        run "$fish_bin" --no-config -n "$fish_file"
        assert_success
    done
}

@test "python scripts/sops-policy.py parses" {
    run python3 -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' \
        "$dotfiles_root/scripts/sops-policy.py"
    assert_success
}
