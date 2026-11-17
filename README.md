# dotfiles

One mise project for three machines:

| Machine | System |
| --- | --- |
| `smortress` | Fedora CoreOS server |
| `smorespro` | Fedora COSMIC Atomic desktop |
| `smoreswork` | macOS work laptop |

mise owns the tools, dotfiles, desktop packages, bootstrap task, and login
shell; Git holds the configuration. There is no symlink installer and no second
configuration manager.

## Bootstrap

The checkout is mise's default dotfiles root, `~/.dotfiles`:

```sh
git clone git@github.com:smores56/dotfiles.git ~/.dotfiles
mise -C ~/.dotfiles bootstrap
```

On a fresh machine, one script installs the latest mise and applies the
inferred set:

```sh
~/.dotfiles/scripts/install-mise.sh
```

On smortress and smorespro, `install-mise.sh` also creates
`/srv/git/github.com/smores56/dotfiles` as a symlink to `~/.dotfiles`. The set
is `identity` on a server, `desktop,identity` on a Linux desktop, and
`desktop,work` on macOS; `DOTFILES_ENVS` overrides it. No values are prompted:
the identity and routing are hardcoded. The login shell is a separate step
because `chsh` asks for a password:

```sh
mise -C ~/.dotfiles bootstrap --only user
```

The full sequence, including the steps that need a human, is in
[docs/manual-steps.md](docs/manual-steps.md). Read it before wiping a disk: the
FIDO2 credential handles only exist there.

## Environments

Environments are additive; an environment only adds files and hooks.

| Environment | Adds |
| --- | --- |
| base | zsh, helix, zellij, yazi, lazygit, television, gh, `sdlc`, global mise files |
| `identity` | git identity templates, `~/.ssh/config`, `allowed_signers` |
| `desktop` | WezTerm, fonts, clipboard and trash helpers, Flatpaks or casks, wallpapers, systemd units, the zsh hand-off |
| `work` | work zsh hooks, work git identity and 1Password signing, the github.com SSH entry, Claude work rules, macOS defaults, work casks |

`install-mise.sh` saves the set in `~/.config/mise/miserc.local.toml`, so no
shell file exports `MISE_ENV`.

## Host prerequisites

| Platform | Before the first bootstrap |
| --- | --- |
| every machine | POSIX shell and coreutils, `curl`, `git`, `tar`, `gzip`, CA certificates |
| Fedora Atomic / CoreOS | nothing more; the image ships `git`, `curl`, and, on desktops, `flatpak` |
| smortress / smorespro | `/srv/git` created once and owned by you: `sudo install -d -o "$USER" -g "$(id -gn)" /srv/git` |
| macOS | Command Line Tools (they provide `git`) and Homebrew; run `scripts/install-homebrew.sh` once, interactively |
| smoreswork | also the 1Password app for its SSH agent and `op-ssh-sign`; the bootstrap installs the `op` CLI |

`install-mise.sh` runs the official installer for the latest stable mise, which
verifies the release checksum and needs `tar` plus `gzip` (or `zstd`).
`zim-build.sh` uses `curl` once for the pinned `zimfw.zsh`. `fc-cache` and
`notify-send` are optional: the pieces that use them degrade without the
binary.

`podman` is the runtime `dev` uses; it ships with Fedora Atomic, and nothing in
the bootstrap needs it. The only root layer is Tailscale
(`rpm-ostree install tailscale`); rclone, a mise tool, handles the wallpaper
sync.

## Layout

| Path | Role |
| --- | --- |
| `mise.toml`, `mise.*.toml` | machine definition and one file per environment |
| `global/` | global tool config and lockfiles, linked to `~/.config/mise` |
| `home/`, `identity/`, `desktop/`, `work/` | dotfiles shared by every machine or added by one environment |
| `scripts/` | installer, bootstrap task, identity and secret materializers |
| `sdlc/` | the stdlib sdlc CLI, its tests, and the phase-skill source |
| `maki/` | Maki configuration, skills, and session helpers |
| `tests/` | source checks and throwaway-HOME behavioural tests |

## Daily use

```sh
mise dot diff                    # what a dotfile apply would change
mise dot apply                   # deploy the checkout's dotfiles
mise bootstrap                   # tools, repos, dotfiles, and the bootstrap task

repos get owner/project          # plain git clone under /srv/git/<host>/<owner>/<repo>
repos list
worktrees new --slug add-gizmo --ticket ABC-123 --type feat
worktrees prune              # dry run; --apply removes what it reported
dev                              # rootless Podman shell for the current checkout
```

`worktrees new` renders the branch name from `git config smores.branchTemplate`
and prints JSON: use its `path`. `dev` prefers podman, uses the repository's
`Containerfile` when present, otherwise the shared
`~/.config/containers/Containerfile.dev`; it never mounts `~/.ssh`, never
forwards tokens, and keeps each checkout's mise installs on its own volume. The
SSH agent socket is opt-in with `DEV_SSH_AGENT=1`.

Personal checkouts live under `/srv/git` on smortress and smorespro, which is
also `ghq.root`; the work Mac keeps work repositories in `~/Blitzy` and only
the `dotfiles` clone in `~/.dotfiles`.

Every dotfile target is absolute or starts with `~/`, and application
directories deploy in `symlink-each` mode. Files that tools rewrite in place
stay local: zsh-abbr's abbreviation file, zimfw's state and completion dump.
`~/.bash_profile` on Fedora is a managed block, not a whole-file entry.
Deployment keeps no history, so recovery is the tagged pre-mise commit plus a
re-apply; `mise dot unapply` removes what mise created. Without
`--force-dotfiles`, mise refuses to replace an existing file and bootstrap
never passes that flag: resolve a conflict by hand.

## Shell

zsh is the only interactive shell, built from pinned upstream plugins under
zimfw with the pure prompt. `~/.zshenv` sets `ZDOTDIR=~/.config/zsh`; the
config sources `conf.d/*.zsh`, zimfw, atuin, and `mise activate zsh`. zimfw
never touches the network at shell start: the bootstrap task downloads the
pinned zimfw release and every module is cloned by `[bootstrap.repos]` at a
commit.

On Linux the zsh binary comes from the mise `conda:zsh` tool; a bootstrap task
links the real binary to `~/.local/bin/zsh`, and a managed block in the stock
`~/.bash_profile` hands an interactive TTY login to it. `bash -ilc` keeps
running bash, so editors resolving their environment are never hijacked. macOS
uses `/bin/zsh`, already in `/etc/shells`; smoreswork sets it with `chsh`
through `[bootstrap.user] login_shell`.

## Identity and secrets

Git identity is fixed: `Sam Mohr <sam@sammohr.dev>` on personal checkouts and
`Sam Mohr <smohr@blitzy.com>` on work checkouts. There are no `[vars]`: signing
key paths, work owners (`blitzy-ai blitzy-platform`), the flat work root, and
the SDLC registry (`smores56/sdlc` personal, `smohr-blitzy/sdlc` work) are all
hardcoded. Tera templates render `~/.config/git/machine.inc` and `work.inc`;
the base `.gitconfig` carries the personal fallback. `scripts/identity.sh`
writes `~/.config/ssh/allowed_signers` from readable public keys.

smoreswork does not apply the `identity` environment. Its git identity is work
everywhere, commits are signed by an SSH key in 1Password through `op-ssh-sign`,
and git reaches github.com over SSH through the 1Password agent. `gh` is a
wrapper at `~/.local/bin/gh` that reads the work token from 1Password per call;
no personal token is on the laptop, the personal `sdlc` registry is not
reachable from it, and `$SDLC_REPO` points at `smohr-blitzy/sdlc`.

Personal machines keep only these secrets:

| Path | Format | Used by |
| --- | --- | --- |
| `sops.yaml` | SOPS ciphertext with `NEURALWATT_API_KEY`, `TINYFISH_API_KEY`, optional `GITHUB_PERSONAL_PAT` | `scripts/secrets.sh` at bootstrap |
| `~/.config/secrets.env` | derived cache, mode 600, `NAME=value` lines | the zsh `maki` launcher, for the Maki process only |
| `~/.config/gh/hosts.yml` | gh's token store, mode 600 | `gh` and `sdlc` |
| `~/.config/sops/keys.age` | passphrase-wrapped age identity | `~/.local/bin/sops-age-key` through `SOPS_AGE_KEY_CMD` |

The bootstrap task decrypts `sops.yaml` once when the age identity exists and
the ciphertext changed, writes the mode-600 provider cache, and logs `gh` in
with the PAT if one is present. smoreswork has no age identity, so it leaves
both alone; the ciphertext in the public repository is harmless there.
Bootstrap needs no GitHub auth: the repository, zim modules, tool downloads,
and `sdlc` source are all in the checkout. `sdlc` is a stdlib script linked by
the base environment, so no private repository is cloned.

Only personal, cross-machine secrets belong in `sops.yaml`, encrypted to the
admin identity by `.sops.yaml`. Work credentials stay in 1Password. Homelab
material (Cloudflare, restic, R2, ingest) stays in homelab-platform, where it
is used. Host and YubiKey private material and the age identity itself never
enter this repository; public keys and `known_hosts` are plain files.

## Tools and packages

CLI tools are pinned per platform in `global/config.toml` and
`global/config.desktop.toml`, with lockfiles covering linux-x64, linux-arm64,
and macos-arm64; `global/config.work.toml` only disables the mise `gh`.
`[settings] locked = true` means an unlocked tool is an install error, not a
silent resolve. Bump one tool at a time:

```sh
# edit the pin, then, once per environment set:
mise lock --global --platform linux-x64,linux-arm64,macos-arm64
```

Desktop apps are user Flatpaks from Flathub on Linux and Homebrew casks into
`~/Applications` on macOS, both declared in `mise.desktop.toml`. Flatpaks
cannot be pinned and install at `latest`. Project-only tools belong to the
repositories that use them, not to the host.

## Maki

```sh
scripts/install-maki.sh      # downloads, verifies, installs ~/.local/bin/maki
maki                         # or the `a` abbreviation
maki-session-search list     # local session history
ms                           # resumes a session
```

The version, target, and sha256 are in `maki/pin.env`; the installer fails
closed if the download does not match both the pin and the release's published
`sha256sums.txt`. A Maki update is a pin bump followed by a re-run; never copy a
release into `~/.local/bin` by hand. Maki talks directly to Neuralwatt and
TinyFish: there is no capability broker, no agent VM, and no memory service.

## Checks

```sh
tests/check.sh                # syntax, TOML, layout, lints, behaviour
tests/check.sh --shellcheck   # also shellcheck every script
```

`tests/bootstrap-test.sh` applies the environments into throwaway HOMEs and
checks symlinks, templates, modes, rendered identity, and conflicts.
`tests/shell-test.sh` starts an interactive zsh and checks the plugins,
abbreviations, prompt, and that the Maki keys stay out of the parent shell.
`tests/handoff-test.sh` covers the smoreswork home-manager handoff, and
`tests/cli.sh` exercises `repos`, `worktrees`, and `dev` against throwaway
repositories. `tests/secrets-test.sh`, `tests/detect-envs-test.sh`, and
`tests/wallpapers-test.sh` cover the SOPS cache, machine-set inference, and the
wallpaper sync. CI runs the same suite and a real Fedora apply lane; the macOS
lanes are opt-in with the `MACOS_CI` repository variable, because hosted macOS
runners are not available to this account.

## Rollout

Rollout is staged with a canary. Tag the pre-mise commit first. smoreswork is
ported in a throwaway HOME, then cut over from the previous manager in one
sitting; smorespro follows with a dry run then an apply; smortress is last,
applied over SSH with a second session held open. A half-applied run is resumed
by re-running bootstrap.
