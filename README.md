# dotfiles

One mise project for three machines:

| Machine | System |
| --- | --- |
| `smortress` | Fedora CoreOS server |
| `smorespro` | Fedora bootc desktop (niri + Noctalia) |
| `smoreswork` | macOS work laptop |

mise owns the tools, dotfiles, desktop packages, bootstrap task, and login
shell; Git holds the configuration. There is no symlink installer and no second
configuration manager.

## Bootstrap

The checkout is mise's default dotfiles root, `~/.dotfiles`:

```sh
git clone https://github.com/smores56/dotfiles.git ~/.dotfiles
mise -C ~/.dotfiles bootstrap
```

On a fresh machine, one script installs the latest mise and applies the
inferred set:

```sh
~/.dotfiles/scripts/install-mise.sh
```

On smortress and smorespro, `install-mise.sh` creates `/srv/git` (one sudo
prompt) and links `/srv/git/github.com/smores56/dotfiles` to `~/.dotfiles`. The set
is `identity` on a server, `desktop,identity` on a Linux desktop, and
`desktop,work` on macOS; `DOTFILES_ENVS` overrides it. The login shell is a separate step
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
| `identity` | git identity templates, `~/.ssh/config` |
| `desktop` | kitty, fonts, clipboard and trash helpers, Flatpaks or casks, wallpapers, systemd units, the bash-to-zsh login hook |
| `work` | work zsh hooks, work git identity, the github.com SSH entry, Claude work rules, macOS defaults, work casks |

`install-mise.sh` saves the set in `~/.config/mise/miserc.local.toml`, so no
shell file exports `MISE_ENV`.

## Host prerequisites

| Platform | Before the first bootstrap |
| --- | --- |
| every machine | POSIX shell and coreutils, `curl`, `git`, `tar`, `gzip`, CA certificates |
| Fedora Atomic / CoreOS | nothing more; the image ships `git`, `curl`, and, on desktops, `flatpak` |
| smortress / smorespro | nothing extra; `install-mise.sh` prompts for sudo once to create `/srv/git` owned by you |
| macOS | Command Line Tools (they provide `git`) and Homebrew; run `scripts/install-homebrew.sh` once, interactively |
| smoreswork | the bootstrap installs the `op` CLI |

`install-mise.sh` runs the official installer for the latest stable mise, which
verifies the release checksum and needs `tar` plus `gzip` (or `zstd`).
`zim-build.sh` uses `curl` once for the pinned `zimfw.zsh`. `fc-cache` and
`notify-send` are optional: the pieces that use them degrade without the
binary.

The host has no rpm-ostree layer: every host package
on smorespro, Tailscale included, comes from
[smorespro-image](https://github.com/smores56/smorespro-image). rclone, a mise
tool, handles the wallpaper sync.

## Layout

| Path | Role |
| --- | --- |
| `mise.toml`, `mise.*.toml` | machine definition and one file per environment |
| `global/` | global tool config and lockfiles, linked to `~/.config/mise` |
| `home/`, `identity/`, `desktop/`, `work/` | dotfiles shared by every machine or added by one environment |
| `scripts/` | installer, bootstrap task, identity and secret materializers |
| `sdlc/` | the stdlib sdlc CLI, its tests, and the skills every agent loads |
| `maki/` | the pinned Maki release metadata |
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
```

`worktrees new` renders the branch name from `git config smores.branchTemplate`
and prints JSON: use its `path`.

Personal checkouts live under `/srv/git` on smortress and smorespro; the work Mac keeps work repositories in `~/Blitzy` and only
the `dotfiles` clone in `~/.dotfiles`.

Every dotfile target is absolute or starts with `~/`, and application
directories deploy in `symlink-each` mode. Files that tools rewrite in place
stay local: zsh-abbr's abbreviation file, zimfw's state and completion dump.
`~/.bash_profile` on Fedora is a managed block, not a whole-file entry.
Deployment keeps no history: `mise dot unapply` removes what mise created, and
a re-apply restores it. Without
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
`Sam Mohr <smohr@blitzy.com>` on work checkouts. Commits are not signed. Work owners (`blitzy-ai blitzy-platform`), the flat work root, and
the SDLC registry (`smores56/sdlc` personal, `smohr-blitzy/sdlc` work) are all
hardcoded. Tera templates render `~/.config/git/machine.inc` and `work.inc`;
the base `.gitconfig` carries the shared git settings.

smoreswork does not apply the `identity` environment. Its git identity is work
everywhere, and `$SDLC_REPO` points at `smohr-blitzy/sdlc`.

Every machine holds one GitHub token, which every zsh exports as `GH_TOKEN`:
`gh` reads it, and git's credential helper (`gh auth git-credential`) hands it
to every https remote. `identity/.gitconfig` rewrites `git@github.com:` and
`ssh://git@github.com/` remotes to https, so old ssh clones use it too. The
work laptop's token is `GITHUB_WORK_PAT`, a classic token with `repo` scope,
because a fine-grained token reaches only one of the two work organizations;
every other machine's is `GITHUB_PERSONAL_PAT`.

Every machine keeps only these secrets:

| Path | Format | Used by |
| --- | --- | --- |
| `sops.yaml` | SOPS ciphertext with `NEURALWATT_API_KEY`, `TINYFISH_API_KEY`, `GITHUB_PERSONAL_PAT`, `GITHUB_WORK_PAT`, `CLOUDFLARE_ACCESS_CLIENT_ID` and `CLOUDFLARE_ACCESS_CLIENT_SECRET` | `scripts/secrets.sh` at bootstrap |
| `~/.config/secrets.env` | derived cache, mode 600, `NAME=value` lines | the zsh `maki` launcher, for the Maki process only |
| `~/.config/github-token` | derived, mode 600, the machine's one token | `.zshenv`, exported as `GH_TOKEN` for `gh`, git, and `sdlc` |
| `~/.config/cloudflare/access.env` | derived, mode 600, `NAME=value` lines | `~/.local/bin/smortress-ssh`, for the Access route to smortress only |
| `~/.config/sops/keys.age` | passphrase-wrapped age identity | `~/.local/bin/sops-age-key` through `SOPS_AGE_KEY_CMD` |
| `~/.config/sops/fido2-identity.txt` | YubiKey age handle, mode 600, usable only with the token | `~/.local/bin/sops-age-key`, which prefers it when present |

The bootstrap task decrypts `sops.yaml` once when the age identity exists and
the ciphertext changed, writes the mode-600 provider cache, and writes the
token file: `GITHUB_WORK_PAT` where `MISE_ENV` includes `work`,
`GITHUB_PERSONAL_PAT` everywhere else. The same decrypt writes the Access
service token to `~/.config/cloudflare/access.env`, which stays out of the
provider cache: only `smortress-ssh` reads it, and only into cloudflared's
environment.
Bootstrap needs no GitHub auth: the repository, zim modules, tool downloads,
and `sdlc` source are all in the checkout. `sdlc` is a stdlib script linked by
the base environment, so no private repository is cloned.

Only cross-machine secrets belong in `sops.yaml`, encrypted by `.sops.yaml` to
the admin identity and, once enrolled, to the YubiKey's FIDO2 recipient.
`sops-age-key` prefers the YubiKey handle and does not fall back, so a host
without the token decrypts only once `~/.config/sops/fido2-identity.txt` is
removed; the work GitHub PAT is the one work credential there.
The Access service token is scoped to the SSH application, so a leak buys
reachability on that one route and nothing else. Homelab
material (Cloudflare, restic, R2, ingest) stays in homelab-platform, where it
is used. Host and YubiKey private material and the age identity itself never
enter this repository; public keys and `known_hosts` are plain files.

## Tools and packages

CLI tools are pinned per platform in `global/config.toml` and
`global/config.desktop.toml`, with lockfiles covering linux-x64, linux-arm64,
and macos-arm64.
`[settings] locked = true` means an unlocked tool is an install error, not a
silent resolve. Bump one tool at a time:

```sh
# edit the pin, then, once per environment set:
mise lock --global --platform linux-x64,linux-arm64,macos-arm64
```

Desktop apps are user Flatpaks from Flathub on Linux and Homebrew casks into
`~/Applications` on macOS, both declared in `mise.desktop.toml`. Flatpaks
cannot be pinned and install at `latest`. kitty, Dolphin and Brave Origin are
not Flatpaks: the smorespro image ships them as system packages, Brave Origin
from Brave's own RPM repository. Project-only tools belong to the
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
reaches TinyFish search through its MCP server. The other tools that server ships stay blocked by a guard in
`init.lua`.

## Checks

```sh
tests/check.sh                # syntax, TOML, guards, behaviour
tests/check.sh --shellcheck   # also shellcheck every script
```

`tests/bootstrap-test.sh` applies the environments into throwaway HOMEs and
checks symlinks, templates, modes, rendered identity, and conflicts.
`tests/shell-test.sh` starts an interactive zsh and checks the plugins,
abbreviations, prompt, and that the Maki keys stay out of the parent shell.
`tests/cli.sh` exercises `repos` and `worktrees` against throwaway
repositories. `tests/secrets-test.sh`, `tests/detect-envs-test.sh`,
`tests/smortress-ssh-test.sh`, and `tests/wallpapers-test.sh` cover the SOPS
cache, machine-set inference, the Access token wrapper, and the wallpaper
sync. CI runs the same suite and a real Fedora apply lane.
