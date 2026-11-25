#!/usr/bin/env bats
# Starts fish on the dotfiles a machine gets, in throwaway HOMEs. No real $HOME
# is touched and nothing here reaches the network: the repos bootstrap step
# would clone the three pinned plugins from GitHub, so the plugins are staged
# fixtures here, and what the real plugin code does in fish is checked by
# tests/apply-lane.sh, which bootstraps a machine for real.
load helpers

mise_bin=${MISE_BIN:-$(command -v mise || true)}
base_path=/usr/bin:/bin:/usr/sbin:/sbin
os=$(uname -s)

# The real binary, not a mise shim: a shim would read this checkout's config.
# Debian and Ubuntu ship fd as fdfind.
real_bin() {  # real_bin <tool>: print its path when it runs
    if [ -n "$mise_bin" ] && "$mise_bin" which "$1" 2>/dev/null; then
        return 0
    fi
    if command -v "$1" 2>/dev/null; then
        return 0
    fi
    [ "$1" = fd ] && command -v fdfind 2>/dev/null
}

# A mise shim whose version is unset is on PATH but fails at exec. Treating it
# as installed turns one environment gap into a pile of misleading failures.
usable_shell() {  # usable_shell <shell>: print its path when it runs
    local bin
    bin=$(command -v "$1" 2>/dev/null) || return 1
    "$bin" -c ':' >/dev/null 2>&1 || return 1
    printf '%s\n' "$bin"
}

fish_bin=${FISH_BIN:-$(real_bin fish || true)}

# The zsh each platform logs in with: macOS's own /bin/zsh reads /etc/zprofile
# (path_helper), which a Nix- or Homebrew-built zsh on PATH does not.
if [ "$os" = Darwin ] && [ -x /bin/zsh ]; then
    zsh_bin=/bin/zsh
else
    zsh_bin=$(usable_shell zsh || true)
fi

# --- fixtures ----------------------------------------------------------------

# mise with a clean environment, trusting only this checkout, so no global or
# user config leaks into the case.
mise_in() {  # mise_in <home> <env set> <args...>
    local home=$1 env=$2
    shift 2
    env -i HOME="$home" PATH="$base_path" TERM=dumb MISE_ENV="$env" \
        MISE_TRUSTED_CONFIG_PATHS="$dotfiles_root" MISE_YES=1 "$mise_bin" -C "$dotfiles_root" "$@"
}

# apply_home <fixture> <env set> <args...>: applies once into
# $BATS_FILE_TMPDIR/<fixture> and records the status the "exits 0" tests assert.
# Applying each environment is the bulk of this suite's runtime, so every test
# copies a fixture instead of applying again.
apply_home() {
    local fixture=$1 env=$2 status=0
    shift 2
    mkdir -p "$BATS_FILE_TMPDIR/$fixture"
    mise_in "$BATS_FILE_TMPDIR/$fixture" "$env" "$@" \
        >"$BATS_FILE_TMPDIR/$fixture.apply.log" 2>&1 || status=$?
    printf '%s\n' "$status" >"$BATS_FILE_TMPDIR/$fixture.status"
}

apply_status() { cat "$BATS_FILE_TMPDIR/$1.status"; }

# The tool farm a machine has in ~/.local/bin, plus stand-ins that make the
# greeting and the desktop guard observable.
bin_farm() {
    local home=$1 tool bin
    mkdir -p "$home/.local/bin" "$home/.ssh"
    ln -s "$fish_bin" "$home/.local/bin/fish"
    for tool in zoxide fzf fd rg; do
        bin=$(real_bin "$tool") || continue
        ln -s "$bin" "$home/.local/bin/$tool"
    done
    printf '#!/bin/sh\necho PFETCH\n' >"$home/.local/bin/pfetch"
    printf '#!/bin/sh\n' >"$home/.local/bin/gtrash"
    chmod +x "$home/.local/bin/pfetch" "$home/.local/bin/gtrash"
}

# config.fish walks these three pinned clones: each needs functions/ to be
# prepended to fish_function_path, and a conf.d glob that matches, or fish
# sources a literal path and dies -- which the "no stderr" assertions catch.
# The clones themselves are the repos step's work, and that step needs GitHub.
stage_plugins() {
    local home=$1 plugin
    for plugin in pure async-prompt done; do
        mkdir -p "$home/.local/share/fish-plugins/$plugin/functions" \
            "$home/.local/share/fish-plugins/$plugin/conf.d"
        printf '# fixture: the pinned clone ships plugin code here\n' \
            >"$home/.local/share/fish-plugins/$plugin/conf.d/fixture.fish"
    done
}

# smoreswork's shell: pyenv, nvm and the mise shims in the employer's shapes,
# and blitzy-dev's helpers in the real file's shape -- top-level resets, a
# switch that unsets the previous env file's variables, hyphenated aliases.
employer_home() {
    local home=$1
    mkdir -p "$home/.pyenv/shims" "$home/.nvm/versions/node/v9.0.0/bin" \
        "$home/.nvm/versions/node/v24.1.0/bin" "$home/.local/share/mise/shims"
    [ -z "$zsh_bin" ] || ln -s "$zsh_bin" "$home/.local/bin/zsh"
    cat >"$home/blitzy_env_functions.sh" <<'EOF'
_BLITZY_CURRENT_ENV_FILE=""
export BLITZY_ENV=""
set_env() { set -a; . "$1"; set +a; }
blitzy_unload_env() { while IFS= read -r l; do unset "${l%%=*}"; done <"$1"; }
blitzy_switch_env() {
    [ -n "$_BLITZY_CURRENT_ENV_FILE" ] && blitzy_unload_env "$_BLITZY_CURRENT_ENV_FILE"
    _BLITZY_CURRENT_ENV_FILE=$2
    set_env "$2"
    export BLITZY_ENV=$1
}
fails() { return 3; }
alias set-env='set_env'
export PATH="$HOME/.local/bin:$PATH"
EOF
    printf 'FOO_A=1\nFOO_B="two words"\n' >"$home/e1.env"
    printf 'FOO_C=3\n' >"$home/e2.env"
}

# The picker fixture sits beside the homes. git reports worktrees by their real
# path, so resolve the file tempdir first; setup_file's own variables do not
# reach the tests, hence the function.
picker_root() { printf '%s/pickers\n' "$(cd -P -- "$BATS_FILE_TMPDIR" && pwd -P)"; }

# What the pickers see: one repo with two worktrees under the repositories root
# those abbreviations render, and a project to search. The bare repo is cloned
# from a local path, so nothing here is remote.
picker_fixtures() {  # picker_fixtures <root>
    local root=$1
    mkdir -p "$root/up" "$root/proj/src"
    git init -q -b main "$root/up"
    git -C "$root/up" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
    git clone -q --bare "$root/up" "$root/github.com/o/r/.git"
    git -C "$root/github.com/o/r" worktree add -q "$root/github.com/o/r/main" main
    git -C "$root/github.com/o/r" worktree add -q -b feat "$root/github.com/o/r/feat" main
    printf 'one\nneedle here\n' >"$root/proj/src/hay.txt"
}

setup_file() {
    [ -n "$mise_bin" ] || skip "mise not installed"
    [ -n "$fish_bin" ] || skip "fish not installed"

    # A personal machine: base plus desktop and identity, as on smorespro. The
    # dotfiles step only: stage_plugins stands in for the repos step's clones.
    h=$BATS_FILE_TMPDIR/personal-home
    bin_farm "$h"
    stage_plugins "$h"
    apply_home personal-home desktop,identity bootstrap --only dotfiles --yes

    # A work machine: desktop and work, as on smoreswork. The employer's helpers
    # exist before the apply, which must leave them alone.
    h=$BATS_FILE_TMPDIR/work-home
    bin_farm "$h"
    stage_plugins "$h"
    employer_home "$h"
    apply_home work-home desktop,work dot apply

    picker_fixtures "$(picker_root)"
}

# use_home <fixture>: a private copy of a prepared HOME. The links into the
# checkout are absolute, so a copy stays valid.
use_home() {
    h=$BATS_TEST_TMPDIR/home
    cp -a "$BATS_FILE_TMPDIR/$1" "$h"
}

# --- fish in a fixture HOME ---------------------------------------------------

# fish_extra carries assignments a test hands fish on top of the clean
# environment: a stale ZDOTDIR, or names fish cannot hold. Empty everywhere else.
fish_extra=()

fish_run() {  # fish_run <home> <fish args...>
    local home=$1
    shift
    (cd "$home" && env -i HOME="$home" PATH="$base_path" TERM=xterm-256color \
        "${fish_extra[@]}" "$home/.local/bin/fish" "$@" </dev/null)
}

fish_at() {  # fish_at <home> <fish args...>: stderr lands in $BATS_TEST_TMPDIR/fish.err
    local home=$1
    shift
    fish_run "$home" 2>"$BATS_TEST_TMPDIR/fish.err" "$@"
}

# The same run with stderr merged into the output, for the cases where the noise
# itself is what the test reads.
fish_merged() {
    local home=$1
    shift
    fish_run "$home" 2>&1 "$@"
}

fi_() { fish_at "$h" -i -c "$1"; }
fc_() { fish_at "$h" -c "$1"; }

# Fish's stderr goes to its own file rather than to $stderr, so a test asserts
# on the file the run wrote.
assert_no_fish_noise() {
    run cat "$BATS_TEST_TMPDIR/fish.err"
    assert_output ""
}

# --- the applies --------------------------------------------------------------

@test "dotfiles apply exits 0 on a personal machine" {
    use_home personal-home
    assert_equal "$(apply_status personal-home)" 0
    # The repos step is not what ran here: the plugin tree is the staged fixture,
    # so no test is quietly reading GitHub's copy.
    run test -e "$h/.local/share/fish-plugins/pure/.git"
    assert_failure
    run test -d "$h/.local/share/fish-plugins/pure/functions"
    assert_success
}

@test "dotfiles apply exits 0 on a work machine" {
    use_home work-home
    assert_equal "$(apply_status work-home)" 0
}

# --- the personal machine ----------------------------------------------------

@test "non-interactive fish imports the shared env" {
    use_home personal-home
    run --separate-stderr fc_ 'echo $PATH[1] $PAGER $EDITOR'
    assert_output "$h/.local/bin bat hx"
    assert_no_fish_noise
}

@test "fish exports GH_TOKEN for agents it starts" {
    use_home personal-home
    printf 'tok-fish\n' >"$h/.config/gh/token"
    run --separate-stderr fc_ 'echo $GH_TOKEN'
    assert_output tok-fish
}

@test "fish drops a ZDOTDIR inherited from an older session" {
    use_home personal-home
    fish_extra=(ZDOTDIR=/old)
    run fish_merged "$h" -c 'set -q ZDOTDIR; and echo leaked; or echo clear'
    assert_output clear
}

@test "fish starts when the environment holds names it cannot" {
    use_home personal-home
    fish_extra=('a.b=1' 'BASH_FUNC_x%%=() { :; }')
    run fish_merged "$h" -c 'echo started'
    assert_output started
}

# The plugins are fixtures, so their own behaviour belongs to
# tests/apply-lane.sh; what config.fish sets before loading them is this.
@test "config.fish configures what pure and done read" {
    use_home personal-home
    run --separate-stderr fi_ 'echo $pure_enable_container_detection'
    assert_output false
    run --separate-stderr fi_ 'echo $__done_min_cmd_duration'
    assert_output 10000
    run --separate-stderr fi_ \
        'string match -rq -- $__done_exclude[1] "hx foo"; and string match -rq -- $__done_exclude[1] claude; and echo yes'
    assert_output yes
}

@test "the greeting is pfetch" {
    use_home personal-home
    run --separate-stderr fi_ fish_greeting
    assert_output PFETCH
}

@test "zoxide jumps with c" {
    use_home personal-home
    [ -e "$h/.local/bin/zoxide" ] || skip "zoxide not installed"
    run --separate-stderr fi_ 'functions -q c; and echo yes'
    assert_output yes
}

@test "interactive startup writes nothing to stderr" {
    use_home personal-home
    run fi_ true
    assert_success
    assert_no_fish_noise
}

# --- zellij tab naming --------------------------------------------------------

# A function shadows any installed helper, and ~/.local/bin is a symlink farm
# into the checkout: writing a stand-in there would edit the repository.
zellij_namer() { printf 'function zellij-tab-name; echo $argv[1] >>%s/tab-name; end' "$BATS_TEST_TMPDIR"; }

@test "a zellij pane names its tab once, after its folder" {
    use_home personal-home
    : >"$BATS_TEST_TMPDIR/tab-name"
    run fi_ "set -gx ZELLIJ 0; $(zellij_namer); emit fish_prompt; emit fish_prompt"
    run cat "$BATS_TEST_TMPDIR/tab-name"
    assert_output "~"
    assert_no_fish_noise
}

@test "no tab is named outside zellij" {
    use_home personal-home
    : >"$BATS_TEST_TMPDIR/tab-name"
    run fi_ "$(zellij_namer); emit fish_prompt"
    run cat "$BATS_TEST_TMPDIR/tab-name"
    assert_output ""
}

# --- abbreviations ------------------------------------------------------------

exp_() {  # exp_ <name>: an abbreviation's expansion, or nothing
    fish_at "$h" -i -c "abbr --show | string match -- 'abbr -a -- $1 *' \
        | string replace -- 'abbr -a -- $1 ' 'printf %s\\n ' | source"
}

@test "the tool abbreviations expand to what they name" {
    use_home personal-home
    run --separate-stderr exp_ e
    assert_output hx
    run --separate-stderr exp_ f
    assert_output yazi
    run --separate-stderr exp_ g
    assert_output lazygit
    run --separate-stderr exp_ l
    assert_output 'eza --icons --group-directories-first -lh'
    run --separate-stderr exp_ m
    assert_output 'mkdir -p'
    run --separate-stderr exp_ t
    assert_output 'zellij a -c main'
    run --separate-stderr exp_ a
    assert_output maki
}

@test "s opens the sdlc picker" {
    use_home personal-home
    run --separate-stderr exp_ s
    assert_output 'sdlc pick'
}

@test "d pulls, bootstraps, and fails when a dotfile ends up unapplied" {
    use_home personal-home
    run --separate-stderr exp_ d
    assert_output "git -C ~/.dotfiles pull --ff-only --no-rebase --autostash && mise -C ~/.dotfiles bootstrap --prune-dotfiles && begin; mise -C ~/.dotfiles dot status --missing --json >/dev/null; or mise -C ~/.dotfiles dot status --missing; end"
}

@test "the clone and remote abbreviations" {
    use_home personal-home
    run --separate-stderr exp_ gw
    assert_output 'git worktree'
    run --separate-stderr exp_ gc
    assert_output 'git get'
    run --separate-stderr exp_ sm
    assert_output 'ssh smortress -t fish'
    run --separate-stderr exp_ sn
    assert_output 'ssh -t root@smoresnet bash -lc fish'
}

@test "copy and paste are fish's clipboard functions" {
    use_home personal-home
    run --separate-stderr exp_ copy
    assert_output fish_clipboard_copy
    run --separate-stderr exp_ paste
    assert_output fish_clipboard_paste
}

@test "ct empties the trash where gtrash exists" {
    use_home personal-home
    run --separate-stderr exp_ ct
    if [ "$os" = Linux ]; then
        assert_output 'gtrash find --rm --force'
    else
        # ct is Linux-only: the desktop lane defines it there and nowhere else.
        assert_output ""
    fi
}

# --- pickers: fzf filters instead of prompting, hx and c report the pick ------

# pick_ <abbr> <query> <dir> [from] [to]: run the picker non-interactively.
# stdin is /dev/null throughout: at a prompt it is the terminal, and rg with no
# path searches a piped stdin instead of the directory.
pick_() {
    local exp
    exp=$(exp_ "$1") || true
    if [ -n "${4:-}" ]; then
        exp=${exp//"$4"/"$5"}
    fi
    (cd "$3" && env -i HOME="$h" PATH="$base_path" TERM=xterm-256color "$h/.local/bin/fish" -i -c "
        function hx; echo OPEN \$argv; end
        function c; echo JUMP \$argv; end
        $(printf '%s' "$exp" | sed "s/fzf/fzf --filter=$2/")" </dev/null) 2>"$BATS_TEST_TMPDIR/pick.err"
}

have_pickers() {
    [ -e "$h/.local/bin/fzf" ] && [ -e "$h/.local/bin/fd" ] && [ -e "$h/.local/bin/rg" ] \
        || skip "fzf, fd or rg not installed"
}

# identity's r lists every checkout under the repositories root, which the
# fixture stands in for.
@test "r lists every worktree of every repo" {
    use_home personal-home
    have_pickers
    pickers=$(picker_root)
    run --separate-stderr pick_ r feat "$h" /srv/git "$pickers"
    assert_output "JUMP $pickers/github.com/o/r/feat"
}

@test "w jumps to a worktree of this repo, never the bare gitdir" {
    use_home personal-home
    have_pickers
    pickers=$(picker_root)
    run --separate-stderr pick_ w feat "$pickers/github.com/o/r/main"
    assert_output "JUMP $pickers/github.com/o/r/feat"
    # The bare gitdir's line is the only one a `(bare)` query can match; the
    # parens stay quoted, or fish would read them as a command substitution.
    run --separate-stderr pick_ w "'(bare)'" "$pickers/github.com/o/r/main"
    assert_output ""
}

@test "ef opens the picked file" {
    use_home personal-home
    have_pickers
    pickers=$(picker_root)
    run --separate-stderr pick_ ef hay "$pickers/proj"
    assert_output "OPEN src/hay.txt"
}

@test "et opens Helix at the matching line" {
    use_home personal-home
    have_pickers
    pickers=$(picker_root)
    run --separate-stderr pick_ et needle "$pickers/proj"
    assert_output "OPEN src/hay.txt:2"
}

@test "a cancelled pick runs nothing and prints nothing" {
    use_home personal-home
    have_pickers
    pickers=$(picker_root)
    run --separate-stderr pick_ ef zzz-no-match "$pickers/proj"
    assert_output ""
    run cat "$BATS_TEST_TMPDIR/pick.err"
    assert_output ""
}

# --- the work machine ---------------------------------------------------------

@test "the work abbreviations differ from the personal ones" {
    use_home work-home
    run --separate-stderr exp_ a
    assert_output claude
    run --separate-stderr exp_ r
    assert_output 'path dirname ~/Blitzy/*/.git ~/Blitzy/*/.worktrees/*/.git | fzf | read f; and c $f'
    run --separate-stderr exp_ gc
    assert_output ""
    run --separate-stderr exp_ sm
    assert_output 'ssh smortress -t fish'
    run --separate-stderr exp_ sn
    assert_output 'ssh -t root@smoresnet bash -lc fish'
}

@test "the employer toolchains follow the mise shims, newest node first" {
    use_home work-home
    run --separate-stderr fi_ \
        'set -l i (contains -i -- ~/.local/share/mise/shims $PATH); echo $PATH[$i..(math $i + 2)]'
    assert_output "$h/.local/share/mise/shims $h/.pyenv/shims $h/.nvm/versions/node/v24.1.0/bin"
}

@test "1Password unlocks with biometrics" {
    use_home work-home
    run --separate-stderr fi_ 'echo $OP_BIOMETRIC_UNLOCK_ENABLED'
    assert_output true
}

@test "a nested work fish adds each toolchain entry once" {
    use_home work-home
    run --separate-stderr fi_ 'fish -i -c "count (string match -- ~/.pyenv/shims \$PATH)"'
    assert_output 1
}

@test "pyenv and nvm find their roots" {
    use_home work-home
    run --separate-stderr fi_ 'echo $PYENV_ROOT $NVM_DIR'
    assert_output "$h/.pyenv $h/.nvm"
}

# The helpers are zsh functions run through a wrapper, so no zsh means no
# wrappers.
@test "every blitzy helper and alias gets a wrapper, private ones excepted" {
    use_home work-home
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    run --separate-stderr fi_ \
        'functions -q set_env set-env blitzy_switch_env fails; and not functions -q _BLITZY_CURRENT_ENV_FILE; and echo yes'
    assert_output yes
}

@test "a helper's exports reach fish" {
    use_home work-home
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    run --separate-stderr fi_ 'set-env ~/e1.env; echo "$FOO_A|$FOO_B"'
    assert_output "1|two words"
}

@test "switching envs unsets the previous env's variables" {
    use_home work-home
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    run --separate-stderr fi_ 'blitzy_switch_env local ~/e1.env; blitzy_switch_env local ~/e2.env
                set -q FOO_A; and echo set; or echo unset; echo $FOO_C $BLITZY_ENV'
    assert_output "$(printf 'unset\n3 local')"
}

@test "a helper's exit status comes back" {
    use_home work-home
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    run --separate-stderr fi_ 'fails; echo $status'
    assert_output 3
}

@test "running helpers leaves PATH as it was" {
    use_home work-home
    [ -n "$zsh_bin" ] || skip "zsh not installed"
    run --separate-stderr fi_ 'set -l p "$PATH"; set-env ~/e1.env; test "$PATH" = "$p"; and echo same'
    assert_output same
}

@test "the work machine starts cleanly" {
    use_home work-home
    run fi_ true
    assert_success
    assert_no_fish_noise
}
