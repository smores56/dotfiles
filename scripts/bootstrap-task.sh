#!/bin/sh
# The `bootstrap` task: what mise does not manage declaratively. Runs after the
# tools on every `mise bootstrap`, so every step is safe to repeat.
set -eu

log() { printf 'bootstrap: %s\n' "$*" >&2; }

# A fresh machine's caller has neither ~/.local/bin (mise) nor the shims (gh,
# for secrets.sh) on PATH.
PATH=$HOME/.local/bin:${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:$PATH
export PATH

# The checkout this script lives in: the only place mise reads mise.work.toml.
repo_root=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)

# mise creates ~/.ssh 0755 and copies files 0644; ssh refuses both. The key
# itself is a sops secret, so scripts/secrets.sh owns its mode; this only holds
# the directory and repairs a key delivered under an older mode.
tighten_ssh_dir() {
    [ -d "$HOME/.ssh" ] && chmod 700 "$HOME/.ssh"
    [ -f "$HOME/.ssh/id_smortress" ] && chmod 600 "$HOME/.ssh/id_smortress"
    return 0
}

# mise resolves a tool version from the invocation cwd upward, so a shim works
# only inside this checkout with MISE_ENV=work set. launchd runs at `/` and ssh
# runs a ProxyCommand outside any checkout, so neither can use one: these
# wrappers exec the real binary mise resolves here, and never a shim.
write_wrapper() {  # write_wrapper <name> <absolute target>
    dest=$HOME/.local/bin/$1
    mkdir -p "$HOME/.local/bin"
    {
        printf '#!/bin/sh\n'
        printf '# scripts/bootstrap-task.sh wrote this: %s is a mise tool, and a shim\n' "$1"
        printf '# only resolves inside the dotfiles checkout, which launchd and ssh\n'
        printf '# never start from.\n'
        printf "exec '%s' \"\$@\"\n" "$2"
    } >"$dest.new"
    chmod 755 "$dest.new"
    # Idempotent: an unchanged wrapper keeps its inode and mtime.
    if cmp -s "$dest.new" "$dest"; then
        rm -f "$dest.new"
    else
        mv -f "$dest.new" "$dest"
    fi
}

install_tailscale_wrappers() {
    [ "$(uname -s)" = Darwin ] || return 0
    for tool in tailscale tailscaled; do
        resolved=$(MISE_ENV=work mise -C "$repo_root" which "$tool" 2>/dev/null) || resolved=
        case $resolved in
            */mise/shims/*)
                log "$tool resolved to the shim $resolved, which needs a cwd inside the checkout"
                return 1
                ;;
            /*) ;;
            *)
                log "cannot resolve $tool: MISE_ENV=work mise -C $repo_root which $tool"
                return 1
                ;;
        esac
        write_wrapper "$tool" "$resolved" || return 1
    done
}

# The work Mac runs tailscaled unprivileged, so it is a LaunchAgent rather than a
# system daemon: no admin, and it dies with the login session.
load_tailscaled_agent() {
    [ "$(uname -s)" = Darwin ] || return 0
    label=dev.sammohr.tailscaled
    plist=$HOME/Library/LaunchAgents/$label.plist
    [ -f "$plist" ] || return 0
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist" \
        || log "could not load $label; load it with launchctl bootstrap by hand"
}

# The work Mac's ssh-agent is a LaunchAgent too, because the sudo tap needs an
# agent that outlives one terminal: ssh -A forwards whatever SSH_AUTH_SOCK names,
# and pam_rssh on smortress signs through it.
load_ssh_agent() {
    [ "$(uname -s)" = Darwin ] || return 0
    label=dev.sammohr.ssh-agent
    plist=$HOME/Library/LaunchAgents/$label.plist
    [ -f "$plist" ] || return 0
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist" \
        || log "could not load $label; load it with launchctl bootstrap by hand"
}

# The sudo credentials are resident sk handles, one per YubiKey, so a fresh
# login needs them added once: without them pam_rssh falls back to the password,
# which is a working path but not the tap. ssh-add asks for a touch here, which
# is why this runs from bootstrap (a hand at the keyboard) and never from a
# login hook. The loader is its own file so the test drives it with stubs.

# A moved checkout root drops the ~/.dotfiles link, which every mise command needs.
link_dotfiles_checkout() {
    [ "$(uname -s)" = Linux ] || return 0
    sh "$(dirname "$0")/link-dotfiles-checkout.sh" \
        || log "dotfiles link unchanged; see scripts/link-dotfiles-checkout.sh"
}

# The Linux laptops get the same agent from a systemd user unit on the socket
# the Mac's LaunchAgent binds. Started here because a fresh host has it linked
# but not yet enabled, and the sudo tap has no other way to find it.
load_ssh_agent_linux() {
    [ "$(uname -s)" = Linux ] || return 0
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl --user enable --quiet ssh-agent.service 2>/dev/null || true
    systemctl --user start ssh-agent.service 2>/dev/null \
        || log "could not start ssh-agent.service; the sudo tap falls back to the password"
}

link_dotfiles_checkout
tighten_ssh_dir
sh "$(dirname "$0")/secrets.sh" \
    || log "secrets refresh failed; run scripts/secrets.sh by hand to see why"
# Before the agent: its plist and the smortress ProxyCommand both exec a wrapper.
install_tailscale_wrappers \
    || log "the tailscaled agent and the smortress ProxyCommand have no wrapper to run"
load_tailscaled_agent
load_ssh_agent
load_ssh_agent_linux
sh "$(dirname "$0")/add-sudo-credential.sh"
