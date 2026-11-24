# dotfiles

My setup for three machines, managed entirely by mise: tools, dotfiles,
desktop apps, and the bootstrap.

| Machine | What it is | Environments |
| --- | --- | --- |
| `smortress` | Fedora CoreOS server | `identity` |
| `smorespro` | Fedora bootc desktop (niri + Noctalia) | `desktop,identity` |
| `smoreswork` | macOS work laptop | `desktop,work` |

## Set up a machine

You need `curl`, `git`, `tar` and `gzip`. On macOS, also install the Command
Line Tools and run `scripts/install-homebrew.sh` once.

On a personal Linux machine, one command does everything; it asks for sudo once
to create `/srv/git`:

```sh
curl -fsSL https://bootstrap.sammohr.dev | sh
mise -C ~/.dotfiles bootstrap --only user   # sets the login shell; asks for your password
```

On the work Mac, clone this repository to `~/.dotfiles` and run
`~/.dotfiles/scripts/install-mise.sh`.

The environments are picked from the machine (see the table above); set
`DOTFILES_ENVS` to override them.

| If it fails with | Do this |
| --- | --- |
| `macOS keeps a normal clone` | run `~/.dotfiles/scripts/install-mise.sh` instead |
| `~/.dotfiles is a real directory` | move it aside and re-run |
| `not a clean-bare clone` | remove the old checkout and re-run |
| mise refusing to replace a file | sort out the conflict by hand, then re-run |

## Day to day

```sh
d                    # pull the dotfiles and re-bootstrap
mise dot diff        # preview what an apply would change
git get owner/repo   # clone a repository (also `gc`)
```

Personal repositories live under `/srv/git/<host>/<owner>/<repo>`, with the
default branch at `<repo>/main` and task worktrees beside it:

```sh
git -C "$repo" worktree add "$repo/<slug>" -b smores/<slug> origin/main
```

`r` jumps to any worktree, `w` to one in the current repository. Work
repositories on the Mac are plain clones in `~/Blitzy`.

## What each environment adds

Everything builds on the base; each environment only adds.

| Environment | Adds |
| --- | --- |
| base | fish, helix, zellij, yazi, lazygit, gh, `sdlc`, the shared env, global mise config |
| `identity` | personal git identity and `git get`, the tailnet `smortress` SSH route, the `r` and `gc` abbreviations |
| `desktop` | kitty, fonts, clipboard and trash helpers, Flatpaks or casks, wallpapers |
| `work` | work env and git identity, work remotes over https, the userspace `tailscale`, Claude work rules, macOS defaults and casks |

fish is the interactive shell. Login shells stay the system's own (bash on
Fedora, zsh on macOS) and only load `~/.config/shell/env.sh`, which fish
imports too.

Git commits as `Sam Mohr <sam@sammohr.dev>` on personal checkouts and
`<smohr@blitzy.com>` on work ones; the work Mac is work everywhere. Each
machine has one GitHub token, exported as `GH_TOKEN` and used by git over
https.

## Secrets

Secrets shared across machines live encrypted in `sops.yaml`. Edit them with
`sops sops.yaml` and commit; the next bootstrap decrypts them into mode-600
files that only their one consumer reads.

| Key | What it is | Lands in |
| --- | --- | --- |
| `NEURALWATT_API_KEY`, `TINYFISH_API_KEY` | from Bitwarden | `~/.config/maki/secrets.env`, for Maki only |
| `GITHUB_PERSONAL_PAT` | fine-grained: Contents read/write on my repos, Issues read/write on `smores56/sdlc` | `~/.config/gh/token` on personal machines |
| `GITHUB_WORK_PAT` | `smohr-blitzy` classic, `repo` scope, at most 366 days (fine-grained can't reach both work orgs) | `~/.config/gh/token` on the work Mac |
| `SMORTRESS_SSH_KEY` | one ed25519 private key for `ssh smortress`; revoking a laptop is a tailnet change, rotating the key one sops edit | `~/.ssh/id_smortress`, mode 600 |

`NEURALWATT_API_KEY`, `TINYFISH_API_KEY` and `SMORTRESS_SSH_KEY` are required:
a cipher without one of them fails the run and leaves the files alone.

Decrypting uses any enrolled YubiKey (`~/.config/sops/fido2-identity.txt`): sops
asks the identity command for each stanza's recipient, so one matching key costs
one touch and no PIN. With no key attached the passphrase-protected admin key
(`~/.config/sops/keys.age`) is offered instead. Neither file is ever committed.

A touch is a bearer grant: with a token attached, the handle file is enough to
derive that key for as long as the attacker keeps it. Keep the tokens with you
and treat the handle file as sensitive metadata. It holds one block per key, a
`# public key: age1…` comment followed by its `AGE-PLUGIN-FIDO2-HMAC-1…` line.

`SOPS_CONFIG` points at `~/.config/sops/sops.yaml`, the one canonical reader set
(admin, the shared machine key, and the three YubiKeys). A repository needs no
`.sops.yaml` of its own; a copy there is only a fallback for a shell that does
not source the dotfiles env. `mise run sops-audit` checks every tracked
ciphertext in the known checkouts against that file.

## Rebuild a machine

**Before wiping a disk**, back up the FIDO2 credential handles; they can't be
recovered afterwards. Copy them, `~/.ssh` and `~/.config/sops` somewhere
off the machine:

```sh
(cd /srv/git/github.com/smores56/nix-config && nix run .#key-backup)
cp -a ~/.ssh ~/.config/sops /media/<usb>/
```

Then install the OS ([smorespro-image](https://github.com/smores56/smorespro-image/blob/main/docs/switch.md)
for the desktop), restore those two directories, and run the setup above.

On a new machine or after a YubiKey reset, add that key's block and re-encrypt.
Answer no to "require a PIN for decryption" and yes to "separate identity"; a
PIN-requiring credential prompts on every unwrap and shares the retry counter
with the login stack.

```sh
age-plugin-fido2-hmac -g >> ~/.config/sops/fido2-identity.txt
chmod 600 ~/.config/sops/fido2-identity.txt
grep '^# public key:' ~/.config/sops/fido2-identity.txt   # the recipients
# Put the new recipient in ~/.config/sops/sops.yaml in place of the reset key's
# &yk anchor; every repo picks it up through SOPS_CONFIG.
sops updatekeys sops.yaml
```

With every key unplugged, this asks for the passphrase exactly once; with one
key attached, it asks for one touch and no PIN:

```sh
sops -d sops.yaml >/dev/null && echo admin-ok
sops -d sops.yaml >/dev/null && echo yubikey-ok   # touch the one key
```

A few things are set once per host, outside the repository:

- every Linux host: `sudo tailscale up`, with MagicDNS and HTTPS certificates on
- smortress: `sudo tailscale serve --bg --set-path /wallpapers /srv/wallpapers`
- smorespro: `noctalia msg color-scheme-set community "Rose Pine Moon"`, since
  Noctalia's GUI state overrides its config file
- the work Mac: no admin, so `tailscaled` is an unprivileged, userspace daemon
  from `~/Library/LaunchAgents/dev.sammohr.tailscaled.plist` (the bootstrap
  loads it), and the one login is
  `tailscale --socket=$HOME/.local/state/tailscale/tailscaled.sock up`
- `tailscale` and `tailscaled` are mise tools in `mise.work.toml`, and a mise
  shim resolves a version only from a cwd inside this checkout, which launchd
  (`/`) and ssh's ProxyCommand never have. The bootstrap therefore writes
  `~/.local/bin/tailscale` and `~/.local/bin/tailscaled`, each a wrapper that
  execs the binary `MISE_ENV=work mise which` resolved; the plist and the work
  `ProxyCommand` both exec those
- the work Mac runs an OpenSSH agent the same way:
  `~/Library/LaunchAgents/dev.sammohr.ssh-agent.plist` binds
  `~/.local/state/ssh/agent.sock`, the bootstrap loads it and adds every
  `~/.ssh/id_smortress_sudo*` handle — enrolment mints one per YubiKey
  (`_1`, `_2`, `_3`), and the agent must hold each, or a spare key's tap falls
  through to the password — and both shells export `SSH_AUTH_SOCK` to that
  socket. `ssh smortress` then forwards it, and `pam_rssh` signs the sudo tap
  through it. Both agents load the handles themselves at start-up — the Linux
  unit with `ExecStartPost`, the Mac's plist by exec'ing
  `scripts/ssh-agent-serve.sh` — so a reboot needs nothing. `ssh-add
  ~/.ssh/id_smortress_sudo_[0-9]*` is only for a host that has not bootstrapped
  since a handle was minted (the `_*` glob would also match the `.pub` halves
  and warn on each); loading asks for no touch, and the touch happens at the
  next `sudo`
- smortress authorizes root only for the keys pinned in homelab-platform's
  `image/rootfs/etc/ssh/sudo_authorized_keys`, and the bootstrap's
  `scripts/check-sudo-pins.sh` compares them with this machine's handles and
  with what its agent holds. A handle the image does not pin authenticates
  nothing, and a pin no handle answers leaves a retired key authorized, so
  drift is a bootstrap line naming the key: fetch a resident handle with
  `ssh-keygen -K` and rename it `id_smortress_sudo_<n>`, or pin or retire it in
  that file (fetch that checkout first). The work Mac has no homelab-platform
  checkout, so it says it cannot check and continues

## Maintenance

Tools are pinned and locked in `global/`; an unlocked tool won't install. Bump
one at a time, then relock:

```sh
mise lock --global --platform linux-x64,linux-arm64,macos-arm64
```

The work-only tools (the Go toolchain that builds `tailscale`, and `tailscale`
itself) are pinned in `mise.work.toml` and lock at the repository root, on the
Mac's platform alone:

```sh
MISE_ENV=work mise lock --platform macos-arm64
```

The `go:` backend builds from source, so its lock entries carry the version and
no checksum; the toolchain it builds with is the tool that does.

Maki is pinned in `maki/pin.env`; bump it and re-run `scripts/install-maki.sh`.

Run the checks with `tests/check.sh` (add `--shellcheck` to lint every script).
