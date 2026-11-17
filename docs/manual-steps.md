# Operator steps

Everything here needs a human at the keyboard: a disk wipe, a root package
layer, a reboot, or a secret. Run the steps in order. Commands are exact; paths
are the ones this repository installs.

## 1. Before wiping the old disk

The FIDO2 credential handles live on the old machine. Back them up first; after
the wipe they are unrecoverable.

```sh
cd ~/repos/github.com/smores56/nix-config
nix run .#key-backup
```

The command prints the directory it wrote. Copy that directory to external
media and confirm it is there before continuing:

```sh
ls -la <printed-directory>
```

Also copy the SSH material off the machine, because it is created by hand and
is not in this repository:

```sh
install -d /media/<usb>/ssh-backup
cp -a ~/.ssh/. /media/<usb>/ssh-backup/
```

Verify the copy before wiping:

```sh
ls -la /media/<usb>/ssh-backup/id_ed25519
```

Nothing else secret is copied from this machine:

- The provider API keys (`NEURALWATT_API_KEY`, `TINYFISH_API_KEY`) are fetched
  from Bitwarden in step 6. There is no `~/.config/secrets.env` on this machine
  to copy: the keys have been read out of sops.
- The sops age identity is required for the Maki provider keys as well as any
  remaining sops-consuming repository, so always back it up:

  ```sh
  install -d /media/<usb>/sops-backup
  cp -a ~/.config/sops/. /media/<usb>/sops-backup/
  ```

## 2. Install Fedora COSMIC Atomic

Write the official Fedora COSMIC Atomic ISO to a USB stick, boot it, and run
the stock installer:

```sh
sudo dd if=<fedora-cosmic-atomic.iso> of=/dev/sdX bs=4M status=progress oflag=sync
```

In the installer:

1. Choose the disk and enable **encryption** (LUKS) for the root filesystem.
   The laptop's root must be encrypted; there is no separate encrypted-home
   step in this repository.
2. Create the user `smores` and set the password.
3. Use the default filesystem layout and finish the install.
4. Reboot into the installed system and unlock the disk.

Do not add third-party repositories or layer packages during the install.

## 3. First login: base tools and the checkout

Open a terminal. The stock image ships `git`, `curl`, and `flatpak`. Restore
the SSH material from step 1 first; the clone below authenticates with it:

```sh
install -d -m 700 ~/.ssh
cp -a /media/<usb>/ssh-backup/. ~/.ssh/
chmod 600 ~/.ssh/id_ed25519
```

Before bootstrapping, restore the sops identity so the task can decrypt the
provider keys:

```sh
install -d -m 700 ~/.config/sops
install -m 600 /media/<usb>/sops-backup/keys.age ~/.config/sops/keys.age
```

Then clone the repository:

```sh
mkdir -p ~/repos/github.com/smores56
git clone git@github.com:smores56/dotfiles.git \
    ~/repos/github.com/smores56/dotfiles
cd ~/repos/github.com/smores56/dotfiles
```

Install the latest mise and apply this machine's set:

```sh
cd ~/repos/github.com/smores56/dotfiles
scripts/install-mise.sh
```

`install-mise.sh` runs the official installer for the latest stable mise
(checksum verified), infers the set (`desktop,identity`
on this desktop), and runs `mise bootstrap` from the latest `main` with
`--config-dir global`. Set `DOTFILES_ENVS=desktop,identity` to override the
inference. The first run prompts for the git identity vars,
which are saved in `$MISE_STATE_DIR/vars.toml` (mode 0700), installs every tool
from the lockfiles, clones the pinned zim modules, applies the dotfiles, and
runs the bootstrap task, which links the Linux zsh binary. The `sdlc` CLI is
a stdlib script linked from the checkout. It uses the network and no sudo.

The login shell stays bash on Linux; an interactive TTY login hands over to
`~/.local/bin/zsh` through the managed block in `~/.bash_profile`.

## 4. Tailscale (the only host layer)

The wallpaper sync uses rclone, a mise tool, so this layer needs only
Tailscale.

```sh
sudo rpm-ostree install tailscale
sudo systemctl reboot
```

After the reboot:

```sh
sudo systemctl enable --now tailscaled
sudo tailscale up
```

Authenticate in the browser window Tailscale opens. Confirm the node:

```sh
tailscale status
```

## 5. Maki and sdlc

```sh
cd ~/repos/github.com/smores56/dotfiles
scripts/install-maki.sh
maki --version
sdlc list
```

The Maki installer verifies the downloaded tarball against `maki/pin.env` and
the release's published `sha256sums.txt`. A mismatch aborts and installs
nothing. An update is a pin bump in `maki/pin.env` followed by a re-run; never
copy a release into `~/.local/bin` by hand.

`sdlc` is `sdlc/sdlc_issues.py` in this checkout, linked to `~/.local/bin/sdlc`
by the identity environment. There is no private clone or install step: update
the source in the repository and re-apply the dotfiles. `sdlc list` must reach
the `smores56/sdlc` registry; it calls `gh`, which uses the PAT from
`sops.yaml` or a one-time `gh auth login`.

## 6. Agent keys and personal token

The local agent's provider keys and an optional personal GitHub token live
encrypted in `sops.yaml`. The bootstrap task decrypts that file once into
`~/.config/secrets.env` (mode 600) when the admin age identity is present and
the ciphertext changed; the zsh `maki` launcher reads only that cache. A
`GITHUB_PERSONAL_PAT` in the same file is passed to
`gh auth login --with-token`, so `gh` and the `sdlc` CLI need no interactive
login. Nothing else inherits the values.

Verify without printing a key:

```sh
test -s ~/.config/secrets.env && echo keys-present
test "$(stat -c %a ~/.config/secrets.env)" = 600 && echo secrets-mode-ok
zsh -ic 'type -q maki && echo maki-launcher-ok'
gh auth status
```

The committed `sops.yaml` is an encrypted template with empty values. Fill it
once from Bitwarden, using the passphrase-wrapped admin identity:

```sh
cd ~/repos/github.com/smores56/dotfiles
sops sops.yaml
```

Set `NEURALWATT_API_KEY` and `TINYFISH_API_KEY` from the named Bitwarden login
items. Optionally set `GITHUB_PERSONAL_PAT` to a fine-grained token with Issues
read/write on `smores56/sdlc` and Metadata read; add Contents read for private
repositories `gh` should clone or read. Save, commit the new ciphertext, and
run the bootstrap task again. A token is optional: without it, run
`gh auth login` once per personal machine.

The desktop Flatpak ships the `bw` CLI if you prefer to read the values from
Bitwarden in a terminal:

```sh
bw() { flatpak run --command=bw com.bitwarden.desktop "$@"; }
bw login
BW_SESSION=$(bw unlock --raw) || { echo 'unlock failed' >&2; exit 1; }
export BW_SESSION
bw get password <neuralwatt-item>
bw get password <tinyfish-item>
unset BW_SESSION
```

`<neuralwatt-item>` and `<tinyfish-item>` are the Bitwarden login item names.
Never commit the plaintext values; `sops` re-encrypts on save. Work credentials
stay in 1Password, not here.

## 7. Re-authorize the Mac's public key

The Mac stays unmanaged except Tailscale and ordinary OpenSSH. Its existing
public key must be registered again on GitHub after the old machine's keys are
retired.

On the Mac:

```sh
cat ~/.ssh/id_ed25519.pub
```

Copy the printed line to the laptop, then on the laptop:

```sh
gh ssh-key list
gh ssh-key delete <id-of-the-retired-machine-key> --yes
gh ssh-key add /path/to/mac-id_ed25519.pub -t "mac"
```

If the laptop should also accept inbound SSH from the Mac, add the same key to
the laptop's authorized keys:

```sh
install -d -m 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
cat /path/to/mac-id_ed25519.pub >> ~/.ssh/authorized_keys
```

Verify from the Mac:

```sh
ssh smores@<laptop-tailscale-name> true && echo mac-to-laptop-ok
```

## 8. Shell hand-off

Linux keeps bash as the login shell and uses the mise zsh for interactive
shells. No `/etc/shells` change and no `chsh` are needed:

```sh
readlink -f ~/.local/bin/zsh        # a binary under ~/.local/share/mise
zsh -ic 'echo $ZSH_VERSION'         # 5.9.x, with zimfw loaded
echo "$SHELL"                       # still bash
env | grep '^CONDA_' || true        # no CONDA_* variables leak
```

Open a new terminal and confirm the interactive shell is zsh. The hand-off
skips any shell with a command string, so `bash -ilc 'echo $BASH_VERSION'`
must stay in bash. If the zsh link is missing, login falls back to bash.

## 9. Verify the machine

```sh
cd ~/repos/github.com/smores56/dotfiles
mise dot status                    # every dotfile target is applied
tests/check.sh                     # source tree checks
mise ls                            # pinned tools are installed
flatpak list --user                # GUI applications are present
maki --version                     # pinned Maki release
sdlc list                          # local sdlc CLI reaches the registry
git config --show-origin user.email # resolves through machine.inc
worktrees list                     # runs inside a checkout
```
