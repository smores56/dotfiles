#!/usr/bin/env bash
# Behavioral tests for install.sh.
#
# Each case installs into a throwaway HOME with a throwaway local.env. No real
# $HOME is touched, nothing is installed, and the network is never used.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
install=$root/install.sh

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }
assert() {
    local desc=$1
    shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else no "$desc"; fi
}
assert_not() {
    local desc=$1
    shift
    if "$@" >/dev/null 2>&1; then no "$desc"; else ok "$desc"; fi
}
is_link_to() { [ -L "$1" ] && [ "$(readlink -- "$1")" = "$2" ]; }

write_local_env() {
    local dest=$1 profile=$2
    cat >"$dest" <<EOF
PROFILE=$profile
GIT_NAME="Test User"
GIT_EMAIL="test@example.com"
GIT_SIGNING_KEY="~/.ssh/id_ed25519.pub"
PERSONAL_OWNER="smores56"
REPOS_ROOT="~/repos"
WORK_EMAIL="work@example.com"
WORK_SIGNING_KEY="~/.ssh/id_work_ed25519.pub"
WORK_OWNERS="blitzy-ai blitzy-platform"
WORK_FLAT_ROOT="~/Blitzy"
EOF
}

# --- first install ---------------------------------------------------------

home1=$tmp/home1
local1=$tmp/local1.env
mkdir -p "$home1/.ssh"
printf 'ssh-ed25519 AAAAtestkey test@example\n' >"$home1/.ssh/id_ed25519.pub"
write_local_env "$local1" personal

if HOME=$home1 DOTFILES_LOCAL_ENV=$local1 bash "$install" >"$tmp/install1.log" 2>&1; then
    ok "install exits 0"
else
    no "install exits 0"
    sed 's/^/     /' "$tmp/install1.log" >&2
fi

assert "links ~/.gitconfig" is_link_to "$home1/.gitconfig" "$root/home/.gitconfig"
assert "links ~/.config/fish/config.fish" \
    is_link_to "$home1/.config/fish/config.fish" "$root/home/.config/fish/config.fish"
assert "links ~/.local/bin/repos" is_link_to "$home1/.local/bin/repos" "$root/home/.local/bin/repos"
assert "links the maki launcher" \
    is_link_to "$home1/.config/fish/functions/maki.fish" \
        "$root/home/.config/fish/functions/maki.fish"
assert "links the mise pin to ~/.config/mise/config.toml" \
    is_link_to "$home1/.config/mise/config.toml" "$root/packages/mise.toml"
assert "links ~/.config/maki/init.lua" \
    is_link_to "$home1/.config/maki/init.lua" "$root/maki/config/init.lua"
assert "links the maki session helper" \
    is_link_to "$home1/.local/bin/maki-session-search" "$root/maki/bin/maki-session-search"
assert "links skill directories" test -L "$home1/.agents/skills/sdlc"
assert "a linked skill file is readable" test -f "$home1/.agents/skills/sdlc/SKILL.md"

assert "root gitconfig includes machine.inc" \
    grep -qx '    path = ~/.config/git/machine.inc' "$home1/.gitconfig"
assert "machine.inc has the active email" \
    grep -qx '    email = "test@example.com"' "$home1/.config/git/machine.inc"
assert "machine.inc selects the personal include" \
    grep -qxF '[includeIf "gitdir:~/repos/github.com/smores56/"]' "$home1/.config/git/machine.inc"
assert "machine.inc selects each work owner" \
    grep -qxF '[includeIf "gitdir:~/repos/github.com/blitzy-platform/"]' "$home1/.config/git/machine.inc"
assert "machine.inc selects the flat work root" \
    grep -qxF '[includeIf "gitdir:~/Blitzy/"]' "$home1/.config/git/machine.inc"
assert "machine.inc selects work by scp-style remote URL" \
    grep -qxF '[includeIf "hasconfig:remote.*.url:git@github.com:blitzy-ai/**"]' \
        "$home1/.config/git/machine.inc"
assert "machine.inc selects work by ssh URL" \
    grep -qxF '[includeIf "hasconfig:remote.*.url:ssh://git@github.com/blitzy-ai/**"]' \
        "$home1/.config/git/machine.inc"
assert "machine.inc selects work by https URL" \
    grep -qxF '[includeIf "hasconfig:remote.*.url:https://github.com/blitzy-ai/**"]' \
        "$home1/.config/git/machine.inc"
assert "machine.inc selects the personal owner by remote URL" \
    grep -qxF '[includeIf "hasconfig:remote.*.url:git@github.com:smores56/**"]' \
        "$home1/.config/git/machine.inc"
assert "the ssh directory is left at mode 700" test "$(stat -c %a "$home1/.ssh")" = 700
assert "generated personal include uses the personal flow" \
    grep -qx '    flow = "local"' "$home1/.config/git/personal.inc"
assert "generated work include uses the work flow" \
    grep -qx '    flow = "pr"' "$home1/.config/git/work.inc"
assert "generated work include uses ticket branches" \
    grep -qx '    branchTemplate = "{ticket}-{slug}"' "$home1/.config/git/work.inc"

assert "the record names the root gitconfig" \
    grep -qx "$home1/.gitconfig" "$home1/.local/state/dotfiles/links"
assert "the record names generated include files" \
    grep -qx "$home1/.config/git/machine.inc" "$home1/.local/state/dotfiles/links"
assert "allowed_signers is generated from the public key" \
    grep -q 'namespaces="git" ssh-ed25519 AAAAtestkey' "$home1/.config/ssh/allowed_signers"
assert "the record names allowed_signers" \
    grep -qx "$home1/.config/ssh/allowed_signers" "$home1/.local/state/dotfiles/links"

# --- idempotence -----------------------------------------------------------

snapshot_links() { find "$1" -type l -printf '%p -> %l\n' | LC_ALL=C sort; }
snapshot_files() { find "$1" -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null; }

links_before=$(snapshot_links "$home1")
files_before=$(snapshot_files "$home1")
if HOME=$home1 DOTFILES_LOCAL_ENV=$local1 bash "$install" >"$tmp/install2.log" 2>&1; then
    ok "second install exits 0"
else
    no "second install exits 0"
    sed 's/^/     /' "$tmp/install2.log" >&2
fi
assert "the symlink set is unchanged" test "$links_before" = "$(snapshot_links "$home1")"
assert "file contents are unchanged" test "$files_before" = "$(snapshot_files "$home1")"
assert_not "second install creates no link" grep -q '^link ' "$tmp/install2.log"
assert_not "second install rewrites no include file" grep -q '^write ' "$tmp/install2.log"

# --- dry run ---------------------------------------------------------------

home2=$tmp/home2
mkdir -p "$home2"
if HOME=$home2 DOTFILES_LOCAL_ENV=$local1 bash "$install" --dry-run >"$tmp/dry.log" 2>&1; then
    ok "dry run exits 0"
else
    no "dry run exits 0"
    sed 's/^/     /' "$tmp/dry.log" >&2
fi
assert "dry run writes no file or symlink" test -z "$(find "$home2" -mindepth 1 -print -quit)"
assert "dry run says it would link" grep -q '^would link ' "$tmp/dry.log"
assert "dry run says it would write" grep -q '^would write ' "$tmp/dry.log"

# --- refusing to overwrite a real file -------------------------------------

home3=$tmp/home3
mkdir -p "$home3"
printf 'real file\n' >"$home3/.gitconfig"
if HOME=$home3 DOTFILES_LOCAL_ENV=$local1 bash "$install" >"$tmp/refuse.log" 2>&1; then
    no "install refuses a real file without --force"
else
    ok "install refuses a real file without --force"
fi
assert "the real file is untouched" grep -qx 'real file' "$home3/.gitconfig"
assert "the real file is still not a symlink" test ! -L "$home3/.gitconfig"
assert "the refusal names the path" \
    grep -q "refusing to overwrite real file $home3/.gitconfig" "$tmp/refuse.log"

if HOME=$home3 DOTFILES_LOCAL_ENV=$local1 bash "$install" --force >"$tmp/force.log" 2>&1; then
    ok "--force replaces the real file"
else
    no "--force replaces the real file"
    sed 's/^/     /' "$tmp/force.log" >&2
fi
assert "--force leaves a symlink" is_link_to "$home3/.gitconfig" "$root/home/.gitconfig"
assert "--force keeps the replaced file as a backup" \
    grep -qx 'real file' "$home3/.gitconfig.bak."*

# --- a symlink this repository does not own is refused ----------------------

home6=$tmp/home6
mkdir -p "$home6"
ln -s /etc/hostname "$home6/.gitconfig"
if HOME=$home6 DOTFILES_LOCAL_ENV=$local1 bash "$install" >"$tmp/foreign.log" 2>&1; then
    no "install refuses a foreign symlink without --force"
else
    ok "install refuses a foreign symlink without --force"
fi
assert "the foreign symlink is untouched" \
    test "$(readlink -- "$home6/.gitconfig")" = /etc/hostname
assert "the refusal names ownership" \
    grep -q 'does not own it' "$tmp/foreign.log"

if HOME=$home6 DOTFILES_LOCAL_ENV=$local1 bash "$install" --force >"$tmp/foreign-force.log" 2>&1; then
    ok "--force replaces a foreign symlink"
else
    no "--force replaces a foreign symlink"
    sed 's/^/     /' "$tmp/foreign-force.log" >&2
fi
assert "--force links the managed file" is_link_to "$home6/.gitconfig" "$root/home/.gitconfig"
assert "--force backs up the foreign symlink" \
    test "$(readlink -- "$home6/.gitconfig.bak."*)" = /etc/hostname

# A link that already points into this repository is ours: relinking it needs
# no --force, because a tracked file moved or the mapping changed.
home7=$tmp/home7
mkdir -p "$home7"
ln -s "$root/home/.config/fish/config.fish" "$home7/.gitconfig"
if HOME=$home7 DOTFILES_LOCAL_ENV=$local1 bash "$install" >"$tmp/owned.log" 2>&1; then
    ok "install relinks a link that points into the repository"
else
    no "install relinks a link that points into the repository"
    sed 's/^/     /' "$tmp/owned.log" >&2
fi
assert "the owned link now points at the managed file" \
    is_link_to "$home7/.gitconfig" "$root/home/.gitconfig"

# --- a symlinked parent cannot carry a write outside the prefix ------------

home8=$tmp/home8
mkdir -p "$home8" "$tmp/outside"
ln -s "$tmp/outside" "$home8/.config"
if HOME=$home8 DOTFILES_LOCAL_ENV=$local1 bash "$install" >"$tmp/escape.log" 2>&1; then
    no "install refuses a symlinked parent outside the prefix"
else
    ok "install refuses a symlinked parent outside the prefix"
fi
assert "nothing was written through the symlinked parent" \
    test -z "$(find "$tmp/outside" -mindepth 1 -print -quit)"
assert "the refusal names the prefix" \
    grep -q 'refusing to write outside the prefix' "$tmp/escape.log"

# --- an orphan link is removed and reported -------------------------------

home9=$tmp/home9
mkdir -p "$home9"
HOME=$home9 DOTFILES_LOCAL_ENV=$local1 bash "$install" >/dev/null 2>&1
ln -s "$root/home/.config/retired-file" "$home9/.config/retired-file"
printf '%s\n' "$home9/.config/retired-file" >>"$home9/.local/state/dotfiles/links"
ln -s /nonexistent/handmade "$home9/.config/handmade"
if HOME=$home9 DOTFILES_LOCAL_ENV=$local1 bash "$install" >"$tmp/orphan.log" 2>&1; then
    ok "install removes an orphan link and exits 0"
else
    no "install removes an orphan link and exits 0"
    sed 's/^/     /' "$tmp/orphan.log" >&2
fi
assert "the orphan link is gone" test ! -L "$home9/.config/retired-file"
assert "the orphan removal is reported" \
    grep -q "unlink $home9/.config/retired-file" "$tmp/orphan.log"
assert "a link the record never named is kept" \
    test "$(readlink -- "$home9/.config/handmade")" = /nonexistent/handmade

# --- the record survives a partially failed run ---------------------------

home10=$tmp/home10
mkdir -p "$home10/.local/bin/repos"
if HOME=$home10 DOTFILES_LOCAL_ENV=$local1 bash "$install" >"$tmp/half.log" 2>&1; then
    no "install fails on a directory at a link target"
else
    ok "install fails on a directory at a link target"
fi
assert "the failed run still writes the record" test -f "$home10/.local/state/dotfiles/links"
assert "the record names what the failed run linked" \
    grep -qxF "$home10/.gitconfig" "$home10/.local/state/dotfiles/links"

# --- identity validation --------------------------------------------------

home11=$tmp/home11
mkdir -p "$home11"
cat >"$tmp/local-badwork.env" <<'EOF'
PROFILE=personal
GIT_NAME="Test User"
GIT_EMAIL="test@example.com"
WORK_EMAIL=""
WORK_OWNERS="blitzy-ai"
EOF
if HOME=$home11 DOTFILES_LOCAL_ENV=$tmp/local-badwork.env bash "$install" >"$tmp/badwork.log" 2>&1; then
    no "install requires WORK_EMAIL when WORK_OWNERS is set"
else
    ok "install requires WORK_EMAIL when WORK_OWNERS is set"
fi
assert "the WORK_EMAIL failure names the variable" \
    grep -q 'WORK_EMAIL is required' "$tmp/badwork.log"

cat >"$tmp/local-badflat.env" <<'EOF'
PROFILE=personal
GIT_NAME="Test User"
GIT_EMAIL="test@example.com"
WORK_FLAT_ROOT="~/Blitzy"
EOF
if HOME=$home11 DOTFILES_LOCAL_ENV=$tmp/local-badflat.env bash "$install" >"$tmp/badflat.log" 2>&1; then
    no "install requires WORK_EMAIL when WORK_FLAT_ROOT is set"
else
    ok "install requires WORK_EMAIL when WORK_FLAT_ROOT is set"
fi

cat >"$tmp/local-noname.env" <<'EOF'
PROFILE=personal
GIT_NAME=""
GIT_EMAIL="test@example.com"
EOF
if HOME=$home11 DOTFILES_LOCAL_ENV=$tmp/local-noname.env bash "$install" >"$tmp/noname.log" 2>&1; then
    no "install refuses an empty GIT_NAME"
else
    ok "install refuses an empty GIT_NAME"
fi
assert "the empty GIT_NAME failure names the variable" grep -q 'GIT_NAME is empty' "$tmp/noname.log"

cat >"$tmp/local-newline.env" <<'EOF'
PROFILE=personal
GIT_NAME=$'Broken\nName'
GIT_EMAIL="test@example.com"
EOF
if HOME=$home11 DOTFILES_LOCAL_ENV=$tmp/local-newline.env bash "$install" >"$tmp/newline.log" 2>&1; then
    no "install refuses a value containing a newline"
else
    ok "install refuses a value containing a newline"
fi
assert "the newline failure names the variable" grep -q 'GIT_NAME contains a newline' "$tmp/newline.log"
assert "the newline failure writes no include file" \
    test ! -e "$home11/.config/git/machine.inc"


# --- work profile ----------------------------------------------------------

home4=$tmp/home4
local4=$tmp/local4.env
mkdir -p "$home4"
write_local_env "$local4" personal
if HOME=$home4 DOTFILES_LOCAL_ENV=$local4 bash "$install" --profile work >"$tmp/work.log" 2>&1; then
    ok "--profile work exits 0"
else
    no "--profile work exits 0"
    sed 's/^/     /' "$tmp/work.log" >&2
fi
assert "work profile uses the work email" \
    grep -qx '    email = "work@example.com"' "$home4/.config/git/machine.inc"
assert "work profile uses the work signing key" \
    grep -qx '    signingkey = "~/.ssh/id_work_ed25519.pub"' "$home4/.config/git/machine.inc"
assert "work profile falls back to the pr flow" \
    grep -qx '    flow = "pr"' "$home4/.config/git/machine.inc"

# --- missing identity fails closed -----------------------------------------

home5=$tmp/home5
mkdir -p "$home5"
if HOME=$home5 DOTFILES_LOCAL_ENV=$tmp/absent.env bash "$install" >"$tmp/absent.log" 2>&1; then
    no "install fails without a local.env identity"
else
    ok "install fails without a local.env identity"
fi
assert "the missing-identity failure names GIT_EMAIL" grep -q 'GIT_EMAIL is empty' "$tmp/absent.log"

# --- no secret material in the linked tree ---------------------------------

if grep -rInE 'BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}' \
        "$root/home" "$root/maki" "$root/packages" >/dev/null 2>&1; then
    no "no secret material in the managed tree"
else
    ok "no secret material in the managed tree"
fi

# --- a work checkout anywhere gets the work identity -----------------------

# Repos under ~/repos are routed by path; a checkout in ~/wip, /tmp or another
# host is only identifiable by its remote URL, and that is what must decide.
git_value() { HOME=$home1 GIT_CONFIG_NOSYSTEM=1 git -C "$1" config "$2" 2>/dev/null; }
mkdir -p "$tmp/wip/work" "$tmp/wip/personal"
git init -q "$tmp/wip/work"
git -C "$tmp/wip/work" remote add origin git@github.com:blitzy-ai/widget.git
git init -q "$tmp/wip/personal"
git -C "$tmp/wip/personal" remote add origin https://github.com/smores56/toy.git
assert "a work checkout outside the repos root gets the work email" \
    test "$(git_value "$tmp/wip/work" user.email)" = "work@example.com"
assert "a work checkout outside the repos root gets the pr flow" \
    test "$(git_value "$tmp/wip/work" smores.flow)" = "pr"
assert "a work checkout outside the repos root gets the work branch template" \
    test "$(git_value "$tmp/wip/work" smores.branchTemplate)" = "{ticket}-{slug}"
assert "a personal checkout outside the repos root keeps the personal flow" \
    test "$(git_value "$tmp/wip/personal" smores.flow)" = "local"
assert "a checkout with no matching remote keeps the fallback identity" \
    test "$(git_value "$tmp" user.email)" = "test@example.com"

# --- wallpapers refuses to run without rsync -------------------------------

if env PATH=/nonexistent "$root/home/.local/bin/wallpapers" sync >"$tmp/wp.log" 2>&1; then
    no "wallpapers sync fails without rsync"
else
    ok "wallpapers sync fails without rsync"
fi
assert "the rsync failure names rsync" grep -q 'rsync is required' "$tmp/wp.log"

# --- the maki launcher owns the provider keys -----------------------------

if command -v fish >/dev/null 2>&1; then
    fh=$tmp/fish-home
    mkdir -p "$fh/.config/fish/functions" "$tmp/fakebin"
    cp "$root/home/.config/fish/functions/maki.fish" "$fh/.config/fish/functions/maki.fish"
    cat >"$tmp/fakebin/maki" <<'EOF'
#!/bin/sh
printf 'neuralwatt=%s\n' "$NEURALWATT_API_KEY"
printf 'tinyfish=%s\n' "$TINYFISH_API_KEY"
EOF
    chmod +x "$tmp/fakebin/maki"
    printf '# comment\nNEURALWATT_API_KEY="quoted-value"\nBROKEN LINE\nOTHER_KEY=zzz\nTINYFISH_API_KEY=tiny\n' \
        >"$fh/.config/secrets.env"
    chmod 644 "$fh/.config/secrets.env"
    out=$(HOME=$fh XDG_CONFIG_HOME=$fh/.config PATH="$tmp/fakebin:$PATH" \
        fish -c 'source $HOME/.config/fish/functions/maki.fish; maki' 2>"$tmp/fish.err")
    case $out in
        *'neuralwatt=quoted-value'*) ok "the launcher strips one layer of matching quotes" ;;
        *) no "the launcher strips one layer of matching quotes" ;;
    esac
    case $out in
        *'tinyfish=tiny'*) ok "the launcher exports both provider keys" ;;
        *) no "the launcher exports both provider keys" ;;
    esac
    assert "the launcher warns about a 0644 secrets file" grep -q 'expected 600' "$tmp/fish.err"
    assert "the launcher warns about a skipped line" grep -q 'skipped (no =)' "$tmp/fish.err"
    assert "the launcher warns about a foreign name" grep -q 'not a Maki provider key' "$tmp/fish.err"
    plain=$(env -u NEURALWATT_API_KEY -u TINYFISH_API_KEY HOME=$fh XDG_CONFIG_HOME=$fh/.config \
        fish -c 'source $HOME/.config/fish/functions/maki.fish; echo "[$NEURALWATT_API_KEY]"' 2>/dev/null)
    assert "the shell itself gets no provider key" test "$plain" = '[]'
else
    skip "maki launcher tests (fish not installed)"
fi

# --- bootstrap installs the pinned sdlc and names rsync -------------------

boot_home=$tmp/boot-home
mkdir -p "$boot_home/.config/mise" "$tmp/bootbin"
printf '[tools]\n' >"$boot_home/.config/mise/config.toml"
for tool in mise uv; do
    printf '#!/bin/sh\nprintf "%s %%s\\n" "$*" >> "$BOOT_LOG"\n' "$tool" >"$tmp/bootbin/$tool"
    chmod +x "$tmp/bootbin/$tool"
done
: >"$tmp/boot.log"
if HOME=$boot_home PATH="$tmp/bootbin:$PATH" BOOT_LOG="$tmp/boot.log" \
        bash "$root/scripts/bootstrap.sh" --skip-flatpaks >"$tmp/boot.out" 2>&1; then
    ok "bootstrap exits 0 with the pinned tools present"
else
    no "bootstrap exits 0 with the pinned tools present"
    sed 's/^/     /' "$tmp/boot.out" >&2
fi
assert "bootstrap installs sdlc with uv" \
    grep -q '^uv tool install --force git+ssh://git@github.com/smores56/sdlc@' "$tmp/boot.log"
assert "the sdlc install is pinned to a full commit" \
    grep -Eq 'sdlc@[0-9a-f]{40}$' "$tmp/boot.log"
assert "bootstrap prints the host layer with rsync" \
    grep -q 'rpm-ostree install tailscale rsync' "$tmp/boot.out"

printf '\n%d checks, %d failed\n' "$((pass + fail))" "$fail"
[ "$fail" -eq 0 ]
