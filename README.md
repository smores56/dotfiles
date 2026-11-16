# dotfiles

Configuration for a Fedora COSMIC Atomic laptop with an encrypted root. The
repository is plain Git and a symlink installer: no configuration manager, no
templating engine, and no package to install. Every file here is either linked
into `$HOME` or read by one of the scripts in `scripts/`.

Four sources, each with one job:

| Source | Owns |
| --- | --- |
| `packages/flatpaks.txt` | GUI applications, installed as user Flatpaks from Flathub |
| `packages/mise.toml` | CLI tool versions, installed by standalone mise |
| `scripts/bootstrap.sh` | the one-time Flatpak, mise, and CLI bootstrap, including the pinned `sdlc` |
| `rpm-ostree` | host packages only; Tailscale and rsync share the one layer |

The coding agent, Maki, is a pinned upstream release installed into
`~/.local/bin`; its configuration and skills live in `maki/`. The `sdlc` CLI
(the issues registry the workflow skills call) is pinned to an upstream commit
and installed by `scripts/bootstrap.sh` with `uv tool install`. The Mac is not
managed by this repository: it keeps Tailscale and ordinary OpenSSH, and
`home/.ssh/config` is portable by hand.

## One-time setup

The full sequence, with the operator-only steps, is in
[docs/manual-steps.md](docs/manual-steps.md). Read it before wiping the old
disk: the FIDO2 credential handles only exist there.

```sh
# 1. Clone into the shared checkout root.
mkdir -p ~/repos/github.com/smores56
git clone git@github.com:smores56/dotfiles.git \
    ~/repos/github.com/smores56/dotfiles
cd ~/repos/github.com/smores56/dotfiles

# 2. Machine identity (untracked).
cp local.env.example local.env
$EDITOR local.env
chmod 600 local.env

# 3. Link the files.
./install.sh --dry-run
./install.sh

# 4. Packages: user Flatpaks, mise, the pinned CLI tools, and `sdlc`.
scripts/bootstrap.sh

# 5. Maki (verified download).
scripts/install-maki.sh
```

Then the root steps: the one package layer, a reboot, and the Tailscale
login (each command below needs root):

```sh
sudo rpm-ostree install tailscale rsync
sudo systemctl reboot
sudo systemctl enable --now tailscaled
sudo tailscale up
```

## Machine identity

`local.env` is an untracked file of plain shell assignments (see
`local.env.example`). `install.sh` sources it, then writes three git include
files: `~/.config/git/machine.inc` carries the global user, the active profile,
and the `includeIf` rules — one set per personal and work owner on the checkout
path under `REPOS_ROOT`, one per remote URL spelling (`git@host:…`, `ssh://`,
`https://`), and one for the flat work root;
`~/.config/git/personal.inc` and `~/.config/git/work.inc` carry that profile's
email, signing key, flow (`local` or `pr`), and branch templates. The URL rules
are what make a work checkout in `~/wip`, `/tmp`, or another host still resolve
to the work identity and `flow = pr`. The include is the last thing in the
checked-in `~/.gitconfig`, so the identity its rules choose is not overridden by
a plain section, and `install.sh --profile work` switches the fallback identity
without touching any tracked file. Re-run `install.sh` after editing
`local.env`.

## What the installer does

`install.sh` symlinks `home/` under `$HOME` at the same relative paths, and
links the sources that do not live under `$HOME` at fixed targets:

| Source | Target |
| --- | --- |
| `home/.gitconfig` | `~/.gitconfig` |
| `home/.config/fish/**` | `~/.config/fish/**` |
| `home/.local/bin/{repos,worktrees,dev,wallpapers,sops-age-key}` | `~/.local/bin/` |
| `home/.config/{helix,zellij,lazygit,yazi,gh,television,containers}` | `~/.config/…` |
| `home/.config/systemd/user/wallpapers.*` | `~/.config/systemd/user/` |
| `home/.ssh/config` | `~/.ssh/config` |
| `packages/mise.toml` | `~/.config/mise/config.toml` |
| `maki/config/**` | `~/.config/maki/**` |
| `maki/skills/*` | `~/.agents/skills/*` |
| `maki/bin/*` | `~/.local/bin/*` |

It is idempotent: a second run reports `ok` for every current link and rewrites
no generated file. `--dry-run` prints every planned action and writes nothing.
A destination is replaced only when this repository already owns it (the link
points into the repository, or the previous record names it). A real file or a
foreign symlink needs `--force`, which moves the victim to
`<dest>.bak.<timestamp>` first; a directory is never removed. Every link it
owns is recorded in `~/.local/state/dotfiles/links` — written from an `EXIT`
trap, so an interrupted run still records what it linked — and the generated
include and signer files are listed there too. When a source disappears from
the repository, the next run unlinks the dangling link and prints it. Nothing
is ever written outside the prefix: a symlinked parent directory is refused.

What it does not do: it never installs packages, runs a package manager, uses
sudo, starts a service, or touches the network. It does not copy secrets.

## Daily use

```sh
# After changing a tracked file, re-link (idempotent; safe to re-run).
./install.sh

# After changing local.env or switching profiles.
./install.sh --profile work

# Follow-ups that a file installer cannot do.
systemctl --user daemon-reload
systemctl --user enable --now wallpapers.timer
```

`wallpapers` syncs `$WALLPAPERS_SOURCE` (default `smortress:/srv/wallpapers/`)
into `~/.cache/wallpapers` and names one file to use; the timer above runs
`wallpapers sync-and-pick` every three hours. COSMIC has no scriptable
wallpaper setting in this branch, so the wrapper maintains the cache and the
pick is applied by hand in the desktop's Appearance settings. `rsync` comes
from the host layer, since no user-level installer provides it.

### `repos`, `worktrees`, and `dev`

```sh
repos get owner/project      # plain git clone under ~/repos/<host>/<owner>/<repo>
repos list
worktrees new --slug add-gizmo --ticket ABC-123 --type feat
worktrees prune              # dry run; --apply removes what it reported
dev                          # rootless Podman shell for the current checkout
```

`repos get` clones with plain `git clone`; work owners listed in
`smores.workOwners` are routed to the flat `smores.workFlat` root instead.
`worktrees new` renders the branch name from `git config smores.branchTemplate`
and prints JSON: use its `path`. Worktrees live in the repository's
`.worktrees/`, so no extra checkout layout is required. The retired `~/ghq`
root is not part of this layout: nothing writes there, and a checkout left
there falls back to the global identity.

`dev` prefers podman, uses the repository's `Containerfile` when present, and
otherwise the shared `~/.config/containers/Containerfile.dev`. It never mounts
`~/.ssh`, never forwards tokens, and keeps each checkout's mise installs on its
own volume. The SSH agent socket is opt-in, because any repository image could
use a forwarded agent to push to every remote the key reaches:
`DEV_SSH_AGENT=1` mounts it for a trusted checkout.

## Packages

`packages/flatpaks.txt` lists the GUI apps. `packages/mise.toml` pins every CLI
tool; bump one at a time, run `mise install`, use it for a day, then commit.
Fish itself comes from mise, so the shell version is in the same pin file.

The base image is not modified except for the Tailscale and rsync layer.
Packages that need to run before login (none today) would be the only reason to
add another layer.

## Maki

```sh
scripts/install-maki.sh      # downloads, verifies, installs ~/.local/bin/maki
maki                         # or the `a` abbreviation
maki-session-search list     # local session history
pick maki-sessions maki-session-resume   # `ms`
```

The version, target, and sha256 are in `maki/pin.env`; the installer fails
closed if the download does not match both the pin and the release's published
`sha256sums.txt`. An update is a pin bump in `maki/pin.env` followed by
`scripts/install-maki.sh`; never copy a release into `~/.local/bin` by hand.
Configuration, permissions, provider definitions, skills, and session helpers
are ordinary files under `maki/`. Maki talks directly to Neuralwatt and
TinyFish: there is no capability broker, no agent VM, and no memory service.
Fresh XDG state is used; nothing is migrated from an old cache.

## Secrets

Nothing secret is tracked, and `install.sh` never writes a secret. Two files
live outside the repository:

| Path | Format | Used by |
| --- | --- | --- |
| `~/.config/secrets.env` | mode 600, `NAME=value` lines (`NEURALWATT_API_KEY`, `TINYFISH_API_KEY`) | the fish `maki` launcher exports them into the Maki process only |
| `~/.config/sops/keys.age` | age-encrypted, passphrase-wrapped identity | `~/.local/bin/sops-age-key`, invoked by sops through `SOPS_AGE_KEY_CMD`, for repositories that use sops |

`local.env` is not a secret file: it holds the machine's git identity and is
ignored only because it is machine-specific.

## Checks

```sh
tests/check.sh                # syntax, TOML, layout, lints, behavior
tests/check.sh --shellcheck   # also shellcheck every script
tests/install-test.sh         # the installer, in a throwaway HOME
```

`tests/install-test.sh` installs into temporary prefixes: it asserts every
symlink and generated include file, asserts a second run changes nothing, and
asserts `--dry-run` writes nothing. `tests/cli.sh` exercises `repos`,
`worktrees`, and `dev` against throwaway repositories and a fake container
engine. CI runs the same suite with shellcheck.
