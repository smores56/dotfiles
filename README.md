# dotfiles

One mise bootstrap project that defines the development environment on three
machines: Fedora CoreOS `smortress`, Fedora COSMIC Atomic `smorespro`, and the
macOS work laptop `smoreswork`. mise owns the tools, the dotfiles, the desktop
packages, the bootstrap task, and the login shell; plain Git is the only other
source of truth. There is no symlink installer and no second configuration
manager.

## Layout

| Path | Role |
| --- | --- |
| `mise.toml` | machine definition: bootstrap repos, base dotfiles, bootstrap task |
| `mise.desktop.toml` | displays: WezTerm, fonts, Flatpaks, casks, wallpapers, bash hand-off |
| `mise.identity.toml` | git and SSH identity, rendered from vars |
| `mise.work.toml` | smoreswork: work identity, 1Password `gh`, macOS defaults |
| `global/` | global tool config and lockfiles, linked to `~/.config/mise` |
| `home/` | dotfiles shared by every machine |
| `identity/`, `desktop/`, `work/` | sources each environment adds |
| `scripts/` | installer, bootstrap task, identity checks, handoff |
| `tests/` | source checks and throwaway-HOME behavioural tests |
| `maki/` | Maki configuration, skills, and session helpers |

Environments are additive, so no exclusion list is ever duplicated:

| Environment | Adds |
| --- | --- |
| base | zsh config, helix, zellij, yazi, lazygit, television, gh, global mise files |
| `identity` | git identity templates, `~/.ssh/config`, `allowed_signers` |
| `desktop` | WezTerm, the font, clipboard and trash helpers, Flatpaks or casks, wallpapers, the TTY shim, systemd units, the zsh hand-off |
| `work` | the work zsh hooks, work git identity and 1Password signing, the github.com SSH entry, the Claude work rules, macOS defaults, the work casks |

Machine sets: smortress `identity`; smorespro `desktop,identity`; smoreswork
`desktop,work`. Each machine saves its set once with `--save-env`, which writes
`miserc.local.toml` under `~/.config/mise`, so no shell file exports
`MISE_ENV`.

## Bootstrap

The full sequence, with the operator-only steps, is in
[docs/manual-steps.md](docs/manual-steps.md). Read it before wiping the old
disk: the FIDO2 credential handles only exist there.

On an existing machine with mise installed:

```sh
mise -C ~/repos/github.com/smores56/dotfiles bootstrap
```

On a machine without mise, `scripts/install-mise.sh` installs the pinned
release after checking its published sha256 and execs the bootstrap:

```sh
cd ~/repos/github.com/smores56/dotfiles
scripts/install-mise.sh "$(git rev-parse HEAD)" desktop,identity
```

The bootstrap applies `[bootstrap]`, `[dotfiles]`, and the tasks from the
checkout. `--from` pins the clone to a commit, not a branch; a rollout bump
passes a new commit with `--update`. Identity answers are prompted once and
saved in `$MISE_STATE_DIR/vars.toml`, never in this repository. The login shell
is a separate step because `chsh` prompts for a password:

```sh
mise -C ~/repos/github.com/smores56/dotfiles bootstrap --only user
```

A dotfile-only apply is `mise -C <checkout> dot apply`; preview it with
`mise -C <checkout> dot diff` or `mise -C <checkout> dot apply --dry-run`.

## Host prerequisites

The bootstrap assumes only what the base system provides:

| Platform | Before the first bootstrap |
| --- | --- |
| every machine | POSIX shell and coreutils, `curl`, `git`, `tar`, `gzip`, and CA certificates |
| Fedora Atomic / CoreOS | nothing more; the stock image ships `git`, `curl`, and, on desktops, `flatpak` |
| macOS | Command Line Tools (they provide `git`) and Homebrew for the casks and `brew:gh`; run `scripts/install-homebrew.sh` once, interactively |
| smoreswork | also the 1Password app for its SSH agent and `op-ssh-sign`; the bootstrap installs the `op` CLI |

`install-mise.sh` runs the official installer at the pinned mise version; it
verifies the release checksum itself and needs `tar` plus `gzip` (or `zstd`),
which the base images ship. `zim-build.sh` uses `curl` once for the pinned
`zimfw.zsh`.

`fc-cache`, `notify-send`, and `timeout` are optional: the pieces that use them
degrade without the binary. The only root layer is Tailscale; rclone, a mise tool,
handles the wallpaper sync.

`podman` is the runtime `dev` uses; it ships with Fedora Atomic, and nothing in
the bootstrap needs it.

## Dotfiles and recovery

Every target is an absolute path or starts with `~/`, and each application
directory is deployed in `symlink-each` mode. Files that tools rewrite in place
are never managed: zsh-abbr's own abbreviation file stays local, and zimfw's
state and completion dump live under `$XDG_CACHE_HOME`. `~/.bash_profile` on
Fedora is a managed block, not a whole-file entry, because the image ships one.

Deployment has no history for symlinked files, so recovery is the tagged
pre-mise commit plus re-apply; `mise dot unapply` removes what mise created.
Without `--force-dotfiles`, mise refuses to replace an existing file and
bootstrap never passes that flag: resolve a conflict by hand.

## Shell

zsh is the only interactive shell, built from pinned upstream plugins under
zimfw with the pure prompt. `~/.zshenv` sets `ZDOTDIR=~/.config/zsh`; the
config sources `conf.d/*.zsh`, zimfw's `init.zsh`, atuin, and
`mise activate zsh`. zimfw never touches the network at shell start: the
bootstrap task downloads the pinned zimfw release and every module is cloned by
`[bootstrap.repos]` at a commit.

On Linux the zsh binary comes from the mise `conda:zsh` tool; a bootstrap task
links the real binary to `~/.local/bin/zsh` and a managed block in the stock
`~/.bash_profile` hands an interactive TTY login to it. `bash -ilc` keeps
running bash, so editors resolving their environment are never hijacked. macOS
uses `/bin/zsh`, already in `/etc/shells`. smoreswork sets it with `chsh`
through `[bootstrap.user] login_shell`.

## Identity and secrets

Git name, email, signing key, personal owner, work owner, and the work flat root
are `[vars]` with prompts and defaults, saved in `$MISE_STATE_DIR/vars.toml`
with directory mode 0700. Tera templates render `~/.config/git/machine.inc`,
`personal.inc`, and `work.inc`; `scripts/identity.sh` rejects control
characters before rendering and writes `~/.config/ssh/allowed_signers` from
readable public keys. Vars are identity only, never tokens or passwords.

smoreswork does not apply the `identity` environment. Its git identity is work
everywhere, commits are signed by an SSH key in 1Password through `op-ssh-sign`,
and git reaches github.com over SSH through the 1Password agent. The `gh` CLI
gets its API token from a 1Password shell plugin; no personal token is on the
laptop, and the private `sdlc` registry is not reachable from it.

Provider keys are tracked only as SOPS ciphertext; the plaintext cache and the
age identity stay outside the repository:

| Path | Format | Used by |
| --- | --- | --- |
| `secrets/maki.sops.yaml` | SOPS-encrypted dotenv with `NEURALWATT_API_KEY` and `TINYFISH_API_KEY` | `scripts/provider-keys.sh` at bootstrap |
| `~/.config/secrets.env` | derived cache, mode 600, `NAME=value` lines | the zsh `maki` launcher exports the two keys into the Maki process only |
| `~/.config/sops/keys.age` | age-encrypted, passphrase-wrapped identity | `~/.local/bin/sops-age-key`, invoked by sops through `SOPS_AGE_KEY_CMD` |

On a personal machine the bootstrap task decrypts the ciphertext when the age
identity exists and the ciphertext changed, and writes the mode-600 cache.
smoreswork has no age identity, so it leaves the cache alone; the ciphertext in
the public repository is harmless there.

## Tools and packages

CLI tools are pinned per platform in `global/config.toml`,
`global/config.desktop.toml`, and `global/config.work.toml`, with lockfiles
covering linux-x64, linux-arm64, and macos-arm64. `[settings] locked = true`
means an unlocked tool is an install error, not a silent resolve. Bump one tool
at a time:

```sh
# edit the pin, then, once per environment set:
mise lock --global --platform linux-x64,linux-arm64,macos-arm64
```

Desktop apps are user Flatpaks from Flathub on Linux and Homebrew casks into
`~/Applications` on macOS, both declared in `mise.desktop.toml`. Flatpaks
cannot be pinned and install at `latest`. The only host layer is Tailscale (`rpm-ostree install tailscale`); nothing
else needs a new layer.

Project-only tools belong to the repositories that use them, not to the host.

## Daily use

```sh
mise dot diff                    # what a dotfile apply would change
mise dot apply                   # deploy the checkout's dotfiles
mise bootstrap                   # tools, repos, dotfiles, and the bootstrap task
```

### `repos`, `worktrees`, and `dev`

```sh
repos get owner/project      # plain git clone under ~/repos/<host>/<owner>/<repo>
repos list
worktrees new --slug add-gizmo --ticket ABC-123 --type feat
worktrees prune              # dry run; --apply removes what it reported
dev                          # rootless Podman shell for the current checkout
```

`worktrees new` renders the branch name from `git config smores.branchTemplate`
and prints JSON: use its `path`. `dev` prefers podman, uses the repository's
`Containerfile` when present, otherwise the shared
`~/.config/containers/Containerfile.dev`; it never mounts `~/.ssh`, never
forwards tokens, and keeps each checkout's mise installs on its own volume.
The SSH agent socket is opt-in with `DEV_SSH_AGENT=1`.

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
repositories. CI runs the same suite and a real Fedora apply lane. The macOS lanes are opt-in
with the `MACOS_CI` repository variable, because hosted macOS runners are not
available to this account; smoreswork is verified by hand until they are.

## Rollout

Rollout is staged with a canary. Tag the pre-mise commit first. smoreswork is
ported in a throwaway HOME, then cut over from the previous manager in one
sitting; smorespro follows with a dry run then an apply; smortress is last,
applied over SSH with a second session held open. A half-applied run is resumed
by rerunning bootstrap after fixing the reported failure.
