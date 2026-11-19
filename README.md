# dotfiles

One mise project for three machines:

| Machine | System |
| --- | --- |
| `smortress` | Fedora CoreOS server |
| `smorespro` | Fedora bootc desktop (niri + Noctalia) |
| `smoreswork` | macOS work laptop |

mise owns the tools, dotfiles, desktop packages, bootstrap task, and login
shell. There is no symlink installer and no second configuration manager.

## Bootstrap

A fresh personal Linux machine:

```sh
curl -fsSL https://bootstrap.sammohr.dev | sh
mise -C ~/.dotfiles bootstrap --only user   # login shell; chsh asks for a password
```

`bootstrap.sammohr.dev` is a Cloudflare redirect to `scripts/bootstrap.sh` on
`main`, with an Access bypass scoped to that hostname alone. The script asks
for sudo once to create `/srv/git`, clones the repository clean-bare, adds the
`main` worktree, links `~/.dotfiles` to it, and hands off to
`scripts/install-mise.sh`, which installs mise. The work laptop clones `~/.dotfiles` by hand and runs
`scripts/install-mise.sh`.

`install-mise.sh` passes `--config-dir global`, which links `~/.config/mise` to
`global/`; a bare `mise bootstrap` before that link exists applies only the
dotfiles. The machine set is inferred — `identity` on a server,
`desktop,identity` on a Linux desktop, `desktop,work` on macOS — overridden by
`DOTFILES_ENVS`, and saved in `~/.config/mise/miserc.local.toml`.

| If it fails | Do |
| --- | --- |
| `macOS keeps a normal clone` | run `~/.dotfiles/scripts/install-mise.sh` |
| `~/.dotfiles is a real directory` | move it aside and re-run |
| `not a clean-bare clone` | remove the old checkout and re-run |
| mise refuses to replace a file | resolve the conflict by hand; bootstrap never passes `--force-dotfiles` |

## Rebuilding a machine

Before wiping a disk, back up what exists nowhere else: the FIDO2 credential
handles are unrecoverable afterwards.

```sh
(cd /srv/git/github.com/smores56/nix-config && nix run .#key-backup)  # copy the printed dir off-machine
cp -a ~/.ssh ~/.config/sops /media/<usb>/
```

On the new machine, restore `~/.ssh` and `~/.config/sops` (modes 700/600),
then bootstrap. OS install for smorespro is in
[smorespro-image](https://github.com/smores56/smorespro-image/blob/main/docs/switch.md).

Secrets are edited with `sops sops.yaml`, committed, and delivered by the next
bootstrap:

| Key | Value |
| --- | --- |
| `NEURALWATT_API_KEY`, `TINYFISH_API_KEY` | the Bitwarden items of those names |
| `GITHUB_PERSONAL_PAT` | fine-grained: Contents read/write on your repos, Issues read/write on `smores56/sdlc` |
| `GITHUB_WORK_PAT` | `smohr-blitzy` classic, `repo` scope, at most 366 days (Blitzy enterprise rule) |
| `CLOUDFLARE_ACCESS_*` | a Zero Trust service token (Access → Service Auth) restricted to the SSH app, one-year lifetime |

After a YubiKey reset (or on a new machine), regenerate the age handle, answering
yes to "separate identity", then re-encrypt and prove each identity alone. The
admin key stays enrolled as recovery: the plugin is pre-1.0.

```sh
age-plugin-fido2-hmac -g > ~/.config/sops/fido2-identity.txt && chmod 600 ~/.config/sops/fido2-identity.txt
# after a reset: replace &yubikey in .sops.yaml with the "# public key:" line, then
sops updatekeys sops.yaml
mv ~/.config/sops/fido2-identity.txt{,.off}; sops -d sops.yaml >/dev/null && echo admin-ok
mv ~/.config/sops/fido2-identity.txt{.off,}; sops -d sops.yaml >/dev/null && echo yubikey-ok
```

Once per host: `sudo tailscale up` (MagicDNS and HTTPS certs on in the admin
console); on smortress, `sudo tailscale serve --bg --set-path /wallpapers
/srv/wallpapers`; on smorespro, `noctalia msg color-scheme-set community "Rose
Pine Moon"` (its GUI state outranks the config file).

## Environments

Environments are additive.

| Environment | Adds |
| --- | --- |
| base | fish, the shared env, the `sm` abbreviation, helix, zellij, yazi, lazygit, gh, `sdlc`, global mise files |
| `identity` | git identity templates with `git get`, `~/.ssh/config`, the `r` and `gc` abbreviations |
| `desktop` | kitty, fonts, clipboard and trash helpers, Flatpaks or casks, wallpapers, systemd units |
| `work` | work env and fish hooks, work git identity, the github.com SSH entry, Claude work rules, macOS defaults, work casks |

## Host prerequisites

| Platform | Before the first bootstrap |
| --- | --- |
| every machine | POSIX shell and coreutils, `curl`, `git`, `tar`, `gzip`, CA certificates |
| Fedora Atomic / CoreOS | nothing more |
| macOS | Command Line Tools and Homebrew; run `scripts/install-homebrew.sh` once, interactively |

smorespro has no rpm-ostree layer: every host package comes from
[smorespro-image](https://github.com/smores56/smorespro-image).

## Daily use

```sh
mise dot diff                    # what a dotfile apply would change
mise dot apply                   # deploy the checkout's dotfiles
mise bootstrap                   # tools, repos, dotfiles, and the bootstrap task
d                                # pull the dotfiles and bootstrap

git get owner/project            # or gc: clean-bare clone, default branch beside it
repo=/srv/git/github.com/owner/project
git -C "$repo" worktree add "$repo/<slug>" -b smores/<slug> origin/main
```

Checkouts are worktrees beside a clean-bare gitdir: `<repo>/main` and
`<repo>/<slug>`. `r` picks a worktree of any checkout, `w` one of the current
checkout. The work Mac keeps work repositories flat in `~/Blitzy`.

## Shell

fish is the interactive shell; kitty and zellij start it through its mise shim.
Login shells stay the platform's own (bash on Fedora, `/bin/zsh` on macOS) and
only source `~/.config/shell/env.sh`, the POSIX environment that fish imports in
`conf.d/00-env.fish`.

## Identity and secrets

Git identity is `Sam Mohr <sam@sammohr.dev>` on personal checkouts and
`Sam Mohr <smohr@blitzy.com>` on work checkouts; smoreswork skips `identity`
and is work everywhere. Commits are not signed.

Each machine holds one GitHub token, exported as `GH_TOKEN` and handed to every
https remote by `gh auth git-credential`; `git@github.com:` remotes are
rewritten to https. smoreswork uses `GITHUB_WORK_PAT` (classic, `repo` scope,
because a fine-grained token reaches only one of the two work orgs); every other
machine uses `GITHUB_PERSONAL_PAT`.

| Path | Format | Used by |
| --- | --- | --- |
| `sops.yaml` | SOPS ciphertext: `NEURALWATT_API_KEY`, `TINYFISH_API_KEY`, `GITHUB_PERSONAL_PAT`, `GITHUB_WORK_PAT`, `CLOUDFLARE_ACCESS_CLIENT_ID`, `CLOUDFLARE_ACCESS_CLIENT_SECRET` | `scripts/secrets.sh` at bootstrap |
| `~/.config/maki/secrets.env` | derived, mode 600, `NAME=value` | `~/.local/bin/maki`, for the Maki process only |
| `~/.config/gh/token` | derived, mode 600, the machine's one token | `~/.config/shell/env.sh` as `GH_TOKEN` |
| `~/.config/cloudflare/access.env` | derived, mode 600, `NAME=value` | `~/.local/bin/smortress-ssh`, into cloudflared's environment only |
| `~/.config/sops/keys.age` | passphrase-wrapped admin age identity | `~/.local/bin/sops-age-key` via `SOPS_AGE_KEY_CMD` |
| `~/.config/sops/fido2-identity.txt` | YubiKey age handle, mode 600 | `sops-age-key`, which prefers it and never falls back |

Bootstrap decrypts `sops.yaml` when the age identity exists and the ciphertext
changed. It needs no GitHub auth.

Only cross-machine secrets belong in `sops.yaml`. The Access service token is
scoped to the SSH application, but the other Access applications still accept
any valid service token until their policies name their own. Homelab material
stays in homelab-platform. Private keys and the age identity never enter this
repository.

## Tools

Tools are pinned in `global/config.toml` and `global/config.desktop.toml` with
`locked = true`, so an unlocked tool fails to install. Bump one at a time:

```sh
mise lock --global --platform linux-x64,linux-arm64,macos-arm64
```

Desktop apps are user Flatpaks (Linux, unpinned) and Homebrew casks into
`~/Applications` (macOS), declared in `mise.desktop.toml`.

## Maki

```sh
scripts/install-maki.sh      # verify against maki/pin.env, install ~/.local/libexec/maki
maki                         # the key wrapper, or the `a` abbreviation
```

An update is a pin bump in `maki/pin.env` and a re-run.

## Checks

```sh
tests/check.sh                # syntax, TOML, guards, behavioural tests
tests/check.sh --shellcheck   # also shellcheck every script
```
