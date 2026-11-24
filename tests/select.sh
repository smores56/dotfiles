#!/bin/sh
# Maps changed paths, one per line on stdin, to the behavioural tests that
# cover them. Prints test file names, `all`, or nothing.
#
# Conservative by design: a path no rule claims selects the whole suite, so a
# new file can never fall through to a green run that tested nothing.
set -u

all=false
tests=''

add() {
    case " $tests " in
        *" $1 "*) ;;
        *) tests="$tests $1" ;;
    esac
}

while IFS= read -r path || [ -n "$path" ]; do
    case $path in
        # These decide what runs; changing them can change any result.
        tests/check.sh|tests/lib.sh|tests/select.sh|tests/run-one.sh|.githooks/*) all=true ;;

        tests/*-test.sh) add "${path#tests/}" ;;

        sdlc/*) add sdlc ;;

        # Shell config, fish plugins, and the work machine start fish.
        home/.zshenv|home/.config/shell/*|home/.config/fish/*) add fish-test.sh ;;
        work/.config/shell/*|work/.config/fish/*|work/.config/zsh/*) add fish-test.sh ;;

        home/.config/maki/*|home/.local/bin/maki|scripts/install-maki.sh) add maki-test.sh ;;

        scripts/add-sudo-credential.sh) add add-sudo-credential-test.sh ;;
        scripts/check-sudo-pins.sh) add check-sudo-pins-test.sh ;;
        scripts/detect-envs.sh) add detect-envs-test.sh ;;
        scripts/bootstrap.sh) add bootstrap-script-test.sh ;;
        scripts/link-dotfiles-checkout.sh) add dotfiles-layout-test.sh ;;
        scripts/prune-dotfile-state.sh|home/.config/gh/*) add prune-dotfile-state-test.sh ;;
        scripts/secrets.sh) add secrets-test.sh ;;

        home/.local/bin/sops-age-key|home/.config/sops/*)
            add sops-age-key-test.sh
            add sops-age-key-contract-test.sh ;;
        sops.yaml|scripts/check-sops-recipients.sh) add sops-age-key-contract-test.sh ;;
        scripts/sops-policy.py|home/.config/sops/sops.yaml) add sops-policy-test.sh ;;

        desktop/.local/bin/wallpapers) add wallpapers-test.sh ;;

        identity/.config/git/*) add git-get-test.sh ;;
        home/.config/git/*) add bootstrap-test.sh; add git-get-test.sh ;;

        home/.local/bin/gh-sdlc|home/.config/sdlc/*)
            add gh-sdlc-test.sh ;;

        # Applying dotfiles and the tools they install.
        mise.toml|mise.*.toml|mise.*.lock|global/*|desktop/*|identity/*|work/*)
            add bootstrap-test.sh ;;
        scripts/bootstrap-task.sh|scripts/ssh-agent-serve.sh|scripts/install-*.sh|home/.claude*|home/.local/bin/*)
            add bootstrap-test.sh ;;

        # Documentation and CI-only files change no behaviour.
        *.md|*.mdx|.github/*|.gitignore|LICENSE) ;;

        *) all=true ;;
    esac
done

if $all; then
    printf 'all\n'
else
    printf '%s\n' "${tests# }"
fi
