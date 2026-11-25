#!/usr/bin/env bats
# tests/tags.tsv decides which suites a change selects; these hold it to the
# tree, so a new suite without a row, a stale pattern, or a row naming nothing
# fails here instead of going unnoticed.
load helpers

tags_file=$dotfiles_root/tests/tags.tsv
tags_sh=$dotfiles_root/tests/tags.sh
tab=$(printf '\t')

# Every suite: the converted .bats files and the shell ones still to convert.
suites() {
    find "$dotfiles_root/tests" -maxdepth 1 -type f \( -name '*.bats' -o -name '*-test.sh' \) |
        sed "s|$dotfiles_root/||" | sort
}

tag_of() {
    case $1 in
        tests/*.bats) printf '%s\n' "${1#tests/}" | sed 's/\.bats$//' ;;
        tests/*-test.sh) printf '%s\n' "${1#tests/}" | sed 's/-test\.sh$//' ;;
    esac
}

@test "every suite has a row in tags.tsv" {
    missing=''
    while IFS= read -r suite; do
        name=$(tag_of "$suite")
        grep -qF "$name$tab" "$tags_file" || missing="$missing $name"
    done < <(suites)
    assert_equal "$missing" ""
}

@test "every suite selects itself" {
    bad=''
    while IFS= read -r suite; do
        selected=$(cd "$dotfiles_root" && sh "$tags_sh" "$suite")
        case " $selected " in
            # `all` selects the suite too; a row may claim it either way.
            *" $suite "*|*" all "*) ;;
            *) bad="$bad $suite" ;;
        esac
    done < <(suites)
    assert_equal "$bad" ""
}

@test "every tags.tsv row names a suite that exists" {
    bad=''
    while IFS=$tab read -r tag patterns || [ -n "$tag" ]; do
        case $tag in ''|'#'*|all|none) continue ;; esac
        [ -f "$dotfiles_root/tests/$tag.bats" ] || [ -f "$dotfiles_root/tests/$tag-test.sh" ] ||
            bad="$bad $tag"
    done <"$tags_file"
    assert_equal "$bad" ""
}

@test "every tags.tsv pattern names a path in the tree" {
    set -f  # the patterns are git pathspecs, not file names to expand
    stale=''
    while IFS=$tab read -r tag patterns || [ -n "$tag" ]; do
        case $tag in ''|'#'*) continue ;; esac
        for pattern in $patterns; do
            found=$(git -C "$dotfiles_root" ls-files --cached --others --exclude-standard -- "$pattern")
            [ -n "$found" ] || stale="$stale $pattern"
        done
    done <"$tags_file"
    assert_equal "$stale" ""
}

@test "only documentation paths are claimed by none" {
    set -f  # the patterns are git pathspecs, not file names to expand
    bad=''
    while IFS=$tab read -r tag patterns || [ -n "$tag" ]; do
        [ "$tag" = none ] || continue
        for pattern in $patterns; do
            for path in $(git -C "$dotfiles_root" ls-files --cached --others --exclude-standard -- "$pattern"); do
                case $path in
                    *.md | .github/* | .gitignore) ;;
                    *) bad="$bad $path" ;;
                esac
            done
        done
    done <"$tags_file"
    assert_equal "$bad" ""
}

@test "a change to the table's own test selects every suite" {
    run sh "$tags_sh" tests/tags.bats
    assert_output "all"
}

@test "a path a row claims selects that row's suite" {
    run sh "$tags_sh" scripts/detect-envs.sh
    assert_output "tests/detect-envs.bats"
}

@test "a row naming a shell suite selects that file" {
    run sh "$tags_sh" scripts/secrets.sh
    assert_output "tests/secrets-test.sh"
}

@test "a path several rows claim selects all of them" {
    repo=$BATS_TEST_TMPDIR/repo
    mkdir -p "$repo/tests"
    cp "$tags_sh" "$repo/tests/tags.sh"
    touch "$repo/tests/aaa.bats" "$repo/tests/detect-envs.bats"
    printf 'aaa\tREADME.md\ndetect-envs\tREADME.md\n' >"$repo/tests/tags.tsv"
    run sh "$repo/tests/tags.sh" README.md
    assert_output "tests/aaa.bats
tests/detect-envs.bats"
}

@test "a path no row claims selects every suite" {
    run sh "$tags_sh" brand/new/thing
    assert_output "all"
}

@test "a harness change selects every suite" {
    run sh "$tags_sh" tests/helpers.bash
    assert_output "all"
}

@test "a documentation change selects nothing" {
    run sh "$tags_sh" README.md
    assert_output ""
}

@test "--changed reads the diff against the base" {
    repo=$BATS_TEST_TMPDIR/repo
    mkdir -p "$repo/tests" "$repo/scripts"
    cp "$tags_sh" "$repo/tests/tags.sh"
    cp "$tags_file" "$repo/tests/tags.tsv"
    touch "$repo/tests/detect-envs.bats"
    git -C "$repo" init -q
    git -C "$repo" add tests
    git -C "$repo" -c user.name=t -c user.email=t@t commit -qm base
    cp "$dotfiles_root/scripts/detect-envs.sh" "$repo/scripts/"
    run sh -c "cd '$repo' && sh tests/tags.sh --changed --base HEAD"
    assert_output "tests/detect-envs.bats"
}
