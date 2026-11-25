#!/usr/bin/env bats
# tests/tags.tsv decides which suites a change selects; these hold it to the
# tree, so a new suite without a row, a stale pattern, or a row naming nothing
# fails here instead of going unnoticed.
load helpers

tags_file=$dotfiles_root/tests/tags.tsv

@test "every suite has a row in tags.tsv" {
    missing=''
    for suite in "$dotfiles_root"/tests/*.bats; do
        name=$(basename -- "$suite" .bats)
        grep -qE "^$name	" "$tags_file" || missing="$missing $name"
    done
    assert_equal "$missing" ""
}

@test "every tags.tsv row names a suite that exists" {
    bad=''
    while IFS="$(printf '\t')" read -r tag patterns || [ -n "$tag" ]; do
        case $tag in ''|'#'*|all|none) continue ;; esac
        [ -f "$dotfiles_root/tests/$tag.bats" ] || bad="$bad $tag"
    done <"$tags_file"
    assert_equal "$bad" ""
}

@test "every tags.tsv pattern names a tracked path" {
    stale=''
    while IFS="$(printf '\t')" read -r tag patterns || [ -n "$tag" ]; do
        case $tag in ''|'#'*) continue ;; esac
        for pattern in $patterns; do
            (cd "$dotfiles_root" && compgen -G "$pattern" >/dev/null) || stale="$stale $pattern"
        done
    done <"$tags_file"
    assert_equal "$stale" ""
}

@test "a changed suite claims itself" {
    run sh "$dotfiles_root/tests/tags.sh" --changed tests/prune-dotfile-state.bats
    assert_output "tests/prune-dotfile-state.bats"
}

@test "a path a row claims selects that row's suite" {
    run sh "$dotfiles_root/tests/tags.sh" --changed scripts/prune-dotfile-state.sh
    assert_output "tests/prune-dotfile-state.bats"
}

@test "a path no row claims selects every suite" {
    run sh "$dotfiles_root/tests/tags.sh" --changed brand/new/thing
    assert_output "all"
}

@test "a harness change selects every suite" {
    run sh "$dotfiles_root/tests/tags.sh" --changed tests/helpers.bash
    assert_output "all"
}

@test "a documentation change selects nothing" {
    run sh "$dotfiles_root/tests/tags.sh" --changed README.md
    assert_output ""
}
