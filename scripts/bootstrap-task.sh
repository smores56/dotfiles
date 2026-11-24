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

# launchd has no ExecStartPost, so the Mac's plist execs a script that runs the
# agent in the foreground and loads the sudo credentials into it. The wrapper
# carries the absolute path, because launchd never starts inside the checkout.
install_ssh_agent_serve() {
    [ "$(uname -s)" = Darwin ] || return 0
    write_wrapper ssh-agent-smortress "$repo_root/scripts/ssh-agent-serve.sh"
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

# A fresh host has the wallpaper timer linked but never enabled, so the cache
# stays empty until someone runs it by hand. The timer itself waits two minutes
# after the user manager starts before the first sync.
load_wallpapers_linux() {
    [ "$(uname -s)" = Linux ] || return 0
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl --user enable --quiet wallpapers.timer 2>/dev/null || true
    systemctl --user start wallpapers.timer 2>/dev/null \
        || log "could not start wallpapers.timer; run wallpapers sync by hand"
}

# Google Sans Code carries no emoji, so the terminal falls back to Noto Color
# Emoji for them. One 10 MB file is too big to keep in the repo, so fetch it
# here; the digest is the pin, and a mismatched download is discarded.
install_noto_color_emoji() {
    digest=15671215ab769fdc7162a045d56fd7d7e477c51b04e6b3c761d914d8fdd6cc44
    url=https://raw.githubusercontent.com/googlefonts/noto-emoji/99701e07d3d1fe1bdbcdb14964547f0fd592966f/2D/fonts/NotoColorEmoji.ttf
    case $(uname -s) in
        Darwin) dir=$HOME/Library/Fonts ;;
        *) dir=$HOME/.local/share/fonts ;;
    esac
    dest=$dir/NotoColorEmoji.ttf
    file_digest() {
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$1" | cut -d' ' -f1
        else
            shasum -a 256 "$1" | cut -d' ' -f1
        fi
    }
    if [ -f "$dest" ] && [ "$(file_digest "$dest")" = "$digest" ]; then
        return 0
    fi
    log "installing Noto Color Emoji"
    mkdir -p "$dir"
    rm -f "$dest.new"
    if ! curl -fsSL --retry 3 -o "$dest.new" "$url"; then
        log "could not download Noto Color Emoji"
        rm -f "$dest.new"
        return 1
    fi
    if [ "$(file_digest "$dest.new")" != "$digest" ]; then
        log "Noto Color Emoji checksum mismatch; leaving the old file alone"
        rm -f "$dest.new"
        return 1
    fi
    mv -f "$dest.new" "$dest"
    if [ "$(uname -s)" = Linux ] && command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f >/dev/null 2>&1 || true
    fi
}

link_dotfiles_checkout
tighten_ssh_dir
sh "$(dirname "$0")/secrets.sh" \
    || log "secrets refresh failed; run scripts/secrets.sh by hand to see why"
# Before the agent: its plist and the smortress ProxyCommand both exec a wrapper.
install_tailscale_wrappers \
    || log "the tailscaled agent and the smortress ProxyCommand have no wrapper to run"
load_tailscaled_agent
# Before the agent: the plist it loads execs this wrapper.
install_ssh_agent_serve
load_ssh_agent
load_ssh_agent_linux
load_wallpapers_linux
install_noto_color_emoji \
    || log "terminal emoji will not render; run scripts/bootstrap-task.sh by hand to see why"
# After the agent, never before: the loader is a no-op until the socket is bound.
# The loader is its own file so the test drives it with stubs.
sh "$(dirname "$0")/add-sudo-credential.sh"
# The image pins what may sudo; a handle it does not pin is a touch that falls
# through to the password, and a pin no handle here answers stays authorized.
sh "$(dirname "$0")/check-sudo-pins.sh" \
    || log "the sudo pin check needs attention; see the lines above"
