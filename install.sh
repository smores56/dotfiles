#!/usr/bin/env bash
# install.sh: link this repository's files into $HOME.
#
# Every file under home/ is symlinked to the same relative path under the
# prefix (default $HOME). A few sources outside home/ are linked to fixed
# targets: packages/mise.toml becomes ~/.config/mise/config.toml, maki/config
# becomes ~/.config/maki, maki/skills/* become ~/.agents/skills/*, and
# maki/bin/* become ~/.local/bin/*.
#
# Machine identity comes from an untracked local.env (shell assignments, see
# local.env.example). This script reads it and writes three git include files:
# machine.inc (global user plus the includeIf rules), personal.inc, and
# work.inc. Git then selects the identity per checkout from those includeIf
# rules, by checkout path and by remote URL, so a work checkout anywhere picks
# the work identity. No template engine is involved.
#
# A destination is only ever replaced when this repository already owns it: a
# link into the repository, or a path named in the previous record. Anything
# else needs --force, which moves the victim to <dest>.bak.<timestamp> first.
# The record at ~/.local/state/dotfiles/links is written from an EXIT trap, so
# a run that stops halfway still records what it linked. Entries whose source
# disappeared from the repository are unlinked and reported.
#
# usage: install.sh [--dry-run] [--force] [--profile personal|work]
#                   [--prefix DIR] [--local-env FILE]
set -euo pipefail

repo=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
prefix=${DOTFILES_PREFIX:-${HOME:-}}
dry_run=false
force=false
profile=""
cli_profile=""
local_env=${DOTFILES_LOCAL_ENV:-$repo/local.env}
failures=0
linked=0
written=0
unchanged=0
orphans=0
record=()
prev_record=()
prefix_real=""
state=""
record_file=""
record_ready=false

usage() {
    cat <<'EOF'
usage: install.sh [options]

  --dry-run              print what would happen; write nothing
  --force                replace a real file or a foreign symlink with a
                         symlink, keeping the victim as <dest>.bak.<timestamp>
  --profile personal|work
                         active identity; overrides PROFILE from local.env
  --prefix DIR           install under DIR instead of $HOME
  --local-env FILE       read identity from FILE instead of <repo>/local.env
  --help                 this text

environment:
  DOTFILES_PREFIX        same as --prefix
  DOTFILES_LOCAL_ENV     same as --local-env
EOF
}

say() { printf '%s\n' "$*"; }
warn() { printf 'install.sh: %s\n' "$*" >&2; }
failed() {
    warn "$*"
    failures=$((failures + 1))
}

while [ $# -gt 0 ]; do
    case $1 in
        --dry-run) dry_run=true; shift ;;
        --force) force=true; shift ;;
        --profile)
            [ $# -ge 2 ] || { warn "--profile needs a value"; exit 2; }
            profile=$2
            cli_profile=$2
            shift 2 ;;
        --profile=*) profile=${1#*=}; cli_profile=$profile; shift ;;
        --prefix)
            [ $# -ge 2 ] || { warn "--prefix needs a value"; exit 2; }
            prefix=$2
            shift 2 ;;
        --prefix=*) prefix=${1#*=}; shift ;;
        --local-env)
            [ $# -ge 2 ] || { warn "--local-env needs a value"; exit 2; }
            local_env=$2
            shift 2 ;;
        --local-env=*) local_env=${1#*=}; shift ;;
        -h|--help) usage; exit 0 ;;
        *) warn "unknown argument: $1"; usage >&2; exit 2 ;;
    esac
done

[ -n "$prefix" ] || { warn "no prefix: set HOME or pass --prefix"; exit 2; }
[ -d "$prefix" ] || { warn "prefix is not a directory: $prefix"; exit 2; }
prefix_real=$(cd -P -- "$prefix" && pwd)
state=$prefix/.local/state/dotfiles
record_file=$state/links

if [ -f "$local_env" ]; then
    set -a
    # local.env is the operator's own shell assignments; no untrusted input.
    # shellcheck source=/dev/null
    . "$local_env"
    set +a
else
    warn "no $local_env; using empty identity (link-only run)"
fi

profile=${cli_profile:-${PROFILE:-personal}}
case $profile in
    personal|work) ;;
    *) warn "profile must be personal or work, got: $profile"; exit 2 ;;
esac

GIT_NAME=${GIT_NAME:-}
GIT_EMAIL=${GIT_EMAIL:-}
GIT_SIGNING_KEY=${GIT_SIGNING_KEY:-~/.ssh/id_ed25519.pub}
PERSONAL_OWNER=${PERSONAL_OWNER:-smores56}
REPOS_ROOT=${REPOS_ROOT:-~/repos}
WORK_EMAIL=${WORK_EMAIL:-}
WORK_SIGNING_KEY=${WORK_SIGNING_KEY:-$GIT_SIGNING_KEY}
WORK_OWNERS=${WORK_OWNERS:-}
WORK_FLAT_ROOT=${WORK_FLAT_ROOT:-}

if [ -z "$GIT_EMAIL" ]; then
    warn "GIT_EMAIL is empty; set it in $local_env"
    exit 2
fi
if [ -z "$GIT_NAME" ]; then
    warn "GIT_NAME is empty; set it in $local_env"
    exit 2
fi
if [ "$profile" = work ] && [ -z "$WORK_OWNERS" ]; then
    warn "profile=work needs WORK_OWNERS in $local_env"
    exit 2
fi
# work.inc is emitted whenever a work owner or the flat root is configured, so
# its identity has to exist then too; otherwise the file ships rows with an
# empty email and signing key that git would happily apply to work checkouts.
if [ -n "$WORK_OWNERS" ] || [ -n "$WORK_FLAT_ROOT" ]; then
    if [ -z "$WORK_EMAIL" ]; then
        warn "WORK_OWNERS or WORK_FLAT_ROOT is set, so WORK_EMAIL is required in $local_env"
        exit 2
    fi
fi

# A git config double-quoted value. Backslash and double quote are the only
# characters git needs escaped, and a newline would break the file, so every
# value is checked before any rendering starts: a failure inside command
# substitution could not abort the script, a check here does.
assert_single_line() {
    case $2 in
        *$'\n'*|*$'\r'*) warn "$1 contains a newline"; exit 2 ;;
    esac
}
for pair in \
    "GIT_NAME:$GIT_NAME" \
    "GIT_EMAIL:$GIT_EMAIL" \
    "GIT_SIGNING_KEY:$GIT_SIGNING_KEY" \
    "PERSONAL_OWNER:$PERSONAL_OWNER" \
    "REPOS_ROOT:$REPOS_ROOT" \
    "WORK_EMAIL:$WORK_EMAIL" \
    "WORK_SIGNING_KEY:$WORK_SIGNING_KEY" \
    "WORK_OWNERS:$WORK_OWNERS" \
    "WORK_FLAT_ROOT:$WORK_FLAT_ROOT"; do
    assert_single_line "${pair%%:*}" "${pair#*:}"
done

git_quote() {
    printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

expand_home() {
    case $1 in
        \~/*) printf '%s/%s\n' "${HOME:-$prefix}" "${1#\~/}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# True when a path names something inside this repository.
under_repo() {
    case $1 in
        "$repo"|"$repo"/*) return 0 ;;
    esac
    return 1
}

# The directory a path resolves to, following symlinked parents, without
# creating anything: the longest existing prefix is resolved with cd -P and the
# missing tail is appended literally.
resolve_dir() {
    local dir=$1 existing tail
    existing=$dir
    tail=""
    while [ ! -d "$existing" ]; do
        [ "$existing" = / ] && return 1
        tail="/$(basename -- "$existing")$tail"
        existing=$(dirname -- "$existing")
    done
    existing=$(cd -P -- "$existing" 2>/dev/null && pwd) || return 1
    printf '%s%s\n' "$existing" "$tail"
}

# A symlinked parent must not carry a write outside the prefix.
assert_dir_under_prefix() {
    local dir=$1 resolved
    resolved=$(resolve_dir "$dir") || {
        failed "cannot resolve the directory for $dir"
        return 1
    }
    case $resolved in
        "$prefix_real"|"$prefix_real"/*) return 0 ;;
    esac
    failed "refusing to write outside the prefix: $dir resolves to $resolved"
    return 1
}

dir_mode() {
    stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" 2>/dev/null || printf ''
}

# ensure_dir <dir>: create it inside the prefix, with ~/.ssh at mode 700.
ensure_dir() {
    local dir=$1
    assert_dir_under_prefix "$dir" || return 1
    if [ ! -d "$dir" ]; then
        # A dry run reports the links and writes nothing, directories included.
        $dry_run && return 0
        if ! mkdir -p -- "$dir" 2>/dev/null; then
            failed "cannot create directory: $dir"
            return 1
        fi
    fi
    case $dir in
        "$prefix/.ssh")
            if [ "$(dir_mode "$dir")" != 700 ]; then
                if $dry_run; then
                    say "would chmod 700 $dir"
                    return 0
                fi
                chmod 700 -- "$dir" || { failed "cannot chmod 700 $dir"; return 1; }
                say "chmod 700 $dir"
            fi ;;
    esac
    return 0
}

load_prev_record() {
    local path
    [ -f "$record_file" ] || return 0
    while IFS= read -r path; do
        case $path in
            ''|'#'*) continue ;;
        esac
        prev_record+=("$path")
    done <"$record_file"
}

in_record() {
    local want=$1 path
    for path in ${prev_record[@]+"${prev_record[@]}"}; do
        [ "$path" = "$want" ] && return 0
    done
    return 1
}

# A destination is ours when the link it already holds points into the
# repository, or when the previous record names the destination.
owns_dest() {
    local dest=$1 target=$2
    under_repo "$target" && return 0
    in_record "$dest"
}

backup_path() {
    local dest=$1 stamp candidate n
    stamp=$(date +%Y%m%d%H%M%S)
    candidate=$dest.bak.$stamp
    n=0
    while [ -e "$candidate" ] || [ -L "$candidate" ]; do
        n=$((n + 1))
        candidate=$dest.bak.$stamp.$n
    done
    printf '%s\n' "$candidate"
}

write_record() {
    local path target
    $dry_run && return 0
    $record_ready || return 0
    ensure_dir "$state" || return 0
    {
        printf '# symlinks owned by install.sh; regenerate with install.sh\n'
        {
            for path in ${record[@]+"${record[@]}"}; do
                printf '%s\n' "$path"
            done
            # Links this repository still owns but that this run did not reach:
            # an aborted run must not drop them from the record.
            for path in ${prev_record[@]+"${prev_record[@]}"}; do
                [ -L "$path" ] || continue
                target=$(readlink -- "$path") || continue
                under_repo "$target" || continue
                printf '%s\n' "$path"
            done
        } | LC_ALL=C sort -u
        printf '# include files generated from local.env\n'
        printf '%s\n' \
            "$prefix/.config/git/machine.inc" \
            "$prefix/.config/git/personal.inc" \
            "$prefix/.config/git/work.inc" \
            "$prefix/.config/ssh/allowed_signers"
    } >"$record_file.tmp" && mv -- "$record_file.tmp" "$record_file"
}

finish() {
    local status=$?
    write_record || status=1
    exit "$status"
}
trap finish EXIT

active_email=$GIT_EMAIL
active_key=$GIT_SIGNING_KEY
if [ "$profile" = work ]; then
    active_email=${WORK_EMAIL:-$GIT_EMAIL}
    active_key=${WORK_SIGNING_KEY:-$GIT_SIGNING_KEY}
fi

# One include rule set per owner, by checkout path and by remote URL. The path
# rule covers the shared root; the URL rules cover a work checkout in ~/wip,
# /tmp, or a second host, where only the remote says who owns it.
render_owner_rules() {
    local inc=$1 owner=$2
    printf '[includeIf "gitdir:%s/github.com/%s/"]\n' "$REPOS_ROOT" "$owner"
    printf '    path = ~/.config/git/%s.inc\n' "$inc"
    printf '[includeIf "hasconfig:remote.*.url:git@github.com:%s/**"]\n' "$owner"
    printf '    path = ~/.config/git/%s.inc\n' "$inc"
    printf '[includeIf "hasconfig:remote.*.url:ssh://git@github.com/%s/**"]\n' "$owner"
    printf '    path = ~/.config/git/%s.inc\n' "$inc"
    printf '[includeIf "hasconfig:remote.*.url:https://github.com/%s/**"]\n' "$owner"
    printf '    path = ~/.config/git/%s.inc\n' "$inc"
}

render_machine_inc() {
    local flow=local owner
    printf '# Generated by install.sh from %s; re-run install.sh after editing it.\n' \
        "$(basename "$local_env")"
    printf '[user]\n'
    printf '    name = %s\n' "$(git_quote "$GIT_NAME")"
    printf '    email = %s\n' "$(git_quote "$active_email")"
    printf '    signingkey = %s\n' "$(git_quote "$active_key")"
    if [ "$profile" = work ]; then
        flow="pr"
    fi
    printf '[smores]\n'
    printf '    flow = %s\n' "$(git_quote "$flow")"
    printf '    workFlat = %s\n' "$(git_quote "$WORK_FLAT_ROOT")"
    printf '    workOwners = %s\n' "$(git_quote "$WORK_OWNERS")"
    printf '\n# Personal checkouts, by path and by remote URL.\n'
    render_owner_rules personal "$PERSONAL_OWNER"
    # shellcheck disable=SC2086 # owners are plain space-separated names
    for owner in $WORK_OWNERS; do
        printf '\n# Work checkouts for %s.\n' "$owner"
        render_owner_rules work "$owner"
    done
    if [ -n "$WORK_FLAT_ROOT" ]; then
        printf '\n# The employer flat layout (<dir>/<repo>) is work.\n'
        printf '[includeIf "gitdir:%s/"]\n' "$WORK_FLAT_ROOT"
        printf '    path = ~/.config/git/work.inc\n'
    fi
}

render_profile_inc() {
    # render_profile_inc <email> <key> <flow>
    printf '# Generated by install.sh; re-run install.sh after editing local.env.\n'
    printf '[user]\n'
    printf '    email = %s\n' "$(git_quote "$1")"
    printf '    signingkey = %s\n' "$(git_quote "$2")"
    printf '[smores]\n'
    printf '    flow = %s\n' "$(git_quote "$3")"
    printf '    branchTemplate = "smores/{slug}"\n'
    printf '    branchTemplateUnticketed = "smores/{slug}"\n'
}

render_work_inc() {
    printf '# Generated by install.sh; re-run install.sh after editing local.env.\n'
    printf '[user]\n'
    printf '    email = %s\n' "$(git_quote "${WORK_EMAIL:-$GIT_EMAIL}")"
    printf '    signingkey = %s\n' "$(git_quote "${WORK_SIGNING_KEY:-$GIT_SIGNING_KEY}")"
    printf '[smores]\n'
    printf '    flow = "pr"\n'
    printf '    branchTemplate = "{ticket}-{slug}"\n'
    printf '    branchTemplateUnticketed = "{type}/{slug}"\n'
}

render_allowed_signers() {
    local key
    key=$(expand_home "$GIT_SIGNING_KEY")
    if [ -r "$key" ]; then
        printf '%s namespaces="git" %s\n' "$GIT_EMAIL" "$(cat "$key")"
    fi
    key=$(expand_home "${WORK_SIGNING_KEY:-$GIT_SIGNING_KEY}")
    if [ -r "$key" ]; then
        printf '%s namespaces="git" %s\n' "${WORK_EMAIL:-$GIT_EMAIL}" "$(cat "$key")"
    fi
}

# write_file <dest> <content>: only touches the file when the content differs.
write_file() {
    local dest=$1 content=$2 dir tmp
    dir=$(dirname -- "$dest")
    assert_dir_under_prefix "$dir" || return 1
    if [ -f "$dest" ] && printf '%s\n' "$content" | cmp -s - "$dest"; then
        unchanged=$((unchanged + 1))
        say "ok    $dest"
        return 0
    fi
    if $dry_run; then
        say "would write $dest"
        written=$((written + 1))
        return 0
    fi
    ensure_dir "$dir" || return 1
    tmp=$(mktemp "$dest.XXXXXX") || { failed "cannot create a temporary file for $dest"; return 1; }
    printf '%s\n' "$content" >"$tmp"
    chmod 644 "$tmp"
    mv -- "$tmp" "$dest"
    written=$((written + 1))
    say "write $dest"
}

# render_file <dest> <renderer> [args...]: render into a variable, so a
# renderer that fails is reported instead of silently producing an empty file.
render_file() {
    local dest=$1 content status=0
    shift
    content=$("$@") || status=$?
    if [ "$status" -ne 0 ]; then
        failed "could not render $dest"
        return 1
    fi
    write_file "$dest" "$content"
}

# link_one <source> <dest>
link_one() {
    local src=$1 dest=$2 target backup
    if [ ! -e "$src" ] && [ ! -L "$src" ]; then
        failed "missing source: $src"
        return
    fi
    ensure_dir "$(dirname -- "$dest")" || return
    if [ -L "$dest" ]; then
        target=$(readlink -- "$dest")
        if [ "$target" = "$src" ]; then
            record+=("$dest")
            unchanged=$((unchanged + 1))
            say "ok    $dest"
            return
        fi
        if ! owns_dest "$dest" "$target" && ! $force; then
            failed "refusing to repoint $dest -> $target; this repository does not own it (use --force)"
            return
        fi
        if $dry_run; then
            if owns_dest "$dest" "$target"; then
                say "would relink $dest -> $src"
            else
                say "would relink $dest -> $src (keeping $dest.bak.<timestamp>)"
            fi
            linked=$((linked + 1))
            return
        fi
        if owns_dest "$dest" "$target"; then
            rm -f -- "$dest"
        else
            backup=$(backup_path "$dest")
            mv -- "$dest" "$backup"
            say "backup $dest -> $backup"
        fi
        ln -s -- "$src" "$dest"
        record+=("$dest")
        linked=$((linked + 1))
        say "relink $dest -> $src"
        return
    fi
    if [ -e "$dest" ]; then
        if [ -d "$dest" ]; then
            failed "refusing to replace directory $dest; move it aside"
            return
        fi
        if ! $force; then
            failed "refusing to overwrite real file $dest; use --force"
            return
        fi
        if $dry_run; then
            say "would replace $dest -> $src (keeping $dest.bak.<timestamp>)"
            linked=$((linked + 1))
            return
        fi
        backup=$(backup_path "$dest")
        mv -- "$dest" "$backup"
        ln -s -- "$src" "$dest"
        record+=("$dest")
        linked=$((linked + 1))
        say "replace $dest -> $src (backup $backup)"
        return
    fi
    record+=("$dest")
    if $dry_run; then
        say "would link $dest -> $src"
        linked=$((linked + 1))
        return
    fi
    ln -s -- "$src" "$dest"
    linked=$((linked + 1))
    say "link  $dest -> $src"
}

# link_tree <source-root> <relative-target-root>
link_tree() {
    local source_root=$1 target_root=$2 path rel dest
    while IFS= read -r -d '' path; do
        rel=${path#"$source_root"/}
        if [ -n "$target_root" ]; then
            dest=$prefix/$target_root/$rel
        else
            dest=$prefix/$rel
        fi
        link_one "$path" "$dest"
    done < <(find "$source_root" \( -type f -o -type l \) -print0 | sort -z)
}

# link_children <source-dir> <relative-target-dir>: one symlink per child.
link_children() {
    local source_dir=$1 target_dir=$2 child
    for child in "$source_dir"/*; do
        [ -e "$child" ] || [ -L "$child" ] || continue
        link_one "$child" "$prefix/$target_dir/$(basename -- "$child")"
    done
}

# A source deleted from the repository leaves a dangling link behind. Only
# links the record names are touched, and only when they point into the
# repository, so a hand-made link is never removed.
prune_orphans() {
    local path target
    for path in ${prev_record[@]+"${prev_record[@]}"}; do
        [ -L "$path" ] || continue
        target=$(readlink -- "$path") || continue
        under_repo "$target" || continue
        [ -e "$target" ] && continue
        if $dry_run; then
            say "would unlink $path -> $target (source is gone)"
            orphans=$((orphans + 1))
            continue
        fi
        rm -f -- "$path"
        orphans=$((orphans + 1))
        say "unlink $path -> $target (source is gone)"
    done
}

say "prefix:  $prefix"
say "profile: $profile"
say "environment: $local_env"

load_prev_record
record_ready=true

link_tree "$repo/home" ""

link_one "$repo/packages/mise.toml" "$prefix/.config/mise/config.toml"
link_tree "$repo/maki/config" ".config/maki"
link_children "$repo/maki/skills" ".agents/skills"
link_one "$repo/maki/bin/maki-session-search" "$prefix/.local/bin/maki-session-search"
link_one "$repo/maki/bin/maki-session-resume" "$prefix/.local/bin/maki-session-resume"

render_file "$prefix/.config/git/machine.inc" render_machine_inc
render_file "$prefix/.config/git/personal.inc" \
    render_profile_inc "$GIT_EMAIL" "$GIT_SIGNING_KEY" "local"
render_file "$prefix/.config/git/work.inc" render_work_inc
# Never clobber a populated allowed_signers when the keys are not on this
# machine yet; create it empty once so git has a file to read.
signers=$(render_allowed_signers)
if [ -n "$signers" ]; then
    write_file "$prefix/.config/ssh/allowed_signers" "$signers"
elif [ ! -e "$prefix/.config/ssh/allowed_signers" ]; then
    write_file "$prefix/.config/ssh/allowed_signers" ""
fi

prune_orphans

if [ "$failures" -ne 0 ]; then
    warn "$failures path(s) could not be linked"
    exit 1
fi

if $dry_run; then
    say "dry run complete: $linked to link, $written to write, $orphans to unlink, $unchanged already current"
    say "dry run: no files were written"
    exit 0
fi

# ssh writes known_hosts beside the config, so the directory must exist before
# the first connection.
ensure_dir "$prefix/.config/ssh" || true

say "record: $record_file"
say "installed: $linked linked, $written written, $orphans unlinked, $unchanged already current"
