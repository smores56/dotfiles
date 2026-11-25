#!/usr/bin/env bats
# Every shell script the tree ships passes shellcheck. This runs in the gate
# itself, so a script that only CI's shellcheck version rejects fails a push
# here too, instead of surfacing as a red main.
load ../helpers

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

@test "every shell script passes shellcheck" {
    command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed"
    offenders=''
    while read -r dialect script; do
        # SC3043: `local` is not POSIX, but every real /bin/sh implements it.
        run sh -c 'cd "$1" && shellcheck -x -s "$2" -S warning -e SC3043 "$3"' \
            sh "$dotfiles_root" "$dialect" "$script"
        if [ "$status" -ne 0 ]; then
            offenders="$offenders ${script#"$dotfiles_root"/}"
            printf '%s\n' "$output" >&2
        fi
    done < <(shell_scripts)
    assert_equal "$offenders" ""
}
