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
- `~/.config/sops/` is only needed if a sops-consuming repository stays in use
  (the homelab ones). Back it up only for those, and only while they remain:

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

Then clone the repository:

```sh
mkdir -p ~/repos/github.com/smores56
git clone git@github.com:smores56/dotfiles.git \
    ~/repos/github.com/smores56/dotfiles
cd ~/repos/github.com/smores56/dotfiles
```

Create the machine identity, link the files, and install the packages:

```sh
cp local.env.example local.env
$EDITOR local.env
chmod 600 local.env
./install.sh --dry-run
./install.sh
scripts/bootstrap.sh
```

`bootstrap.sh` installs the user Flatpaks, downloads the pinned mise release,
installs every CLI tool from `packages/mise.toml`, installs the pinned `sdlc`
CLI with `uv tool install`, and prints the root command for step 4. It uses the
network and no sudo.

## 4. Tailscale and rsync (the only host layer)

rsync lives in the same layer: no user-level installer provides it and the
wallpaper sync needs it.

```sh
sudo rpm-ostree install tailscale rsync
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

`sdlc` is installed by `scripts/bootstrap.sh` from the private upstream at the
commit pinned there as `SDLC_REV`. Bump that constant, re-run the bootstrap,
and commit the new pin. `sdlc list` must reach the `smores56/sdlc` registry,
which needs the GitHub credential from step 3.

## 6. Secrets

`~/.config/secrets.env` is never copied from anywhere: fetch the two provider
keys from Bitwarden. The desktop Flatpak ships the `bw` CLI, and this machine
has no separate one.

```sh
bw() { flatpak run --command=bw com.bitwarden.desktop "$@"; }
bw login
BW_SESSION=$(bw unlock --raw) || { echo 'unlock failed' >&2; exit 1; }
export BW_SESSION
install -d -m 700 ~/.config
umask 077
{
    for pair in NEURALWATT_API_KEY:<neuralwatt-item> TINYFISH_API_KEY:<tinyfish-item>; do
        name=${pair%%:*}
        item=${pair#*:}
        value=$(bw get password "$item") || exit 1
        [ -n "$value" ] || { echo "empty Bitwarden item: $item" >&2; exit 1; }
        printf '%s=%s\n' "$name" "$value"
    done
} > ~/.config/secrets.env
chmod 600 ~/.config/secrets.env
unset BW_SESSION
```

Both keys are read from named Bitwarden login items, and a failed or empty
lookup aborts instead of leaving an empty value in the file.

`<neuralwatt-item>` and `<tinyfish-item>` are the Bitwarden login item names.
The file is `NAME=value` lines; the fish `maki` launcher exports the two keys
into the Maki process only, so nothing else run from the shell inherits them.
Confirm the file is mode 600 and the launcher exists, without printing a value:

```sh
test "$(stat -c %a ~/.config/secrets.env)" = 600 && echo secrets-mode-ok
fish -c 'type -q maki; and echo maki-launcher-ok'
```

If a sops-consuming repository is still in use, restore its identity too:

```sh
install -d -m 700 ~/.config/sops
install -m 600 /media/<usb>/sops-backup/keys.age ~/.config/sops/keys.age
```

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

## 8. Optional: fish as the login shell

Fish comes from mise. The stable shim path (not the versioned install path) is
what makes a durable login shell:

```sh
fish_shim="$HOME/.local/share/mise/shims/fish"
sudo sh -c "printf '%s\n' '$fish_shim' >> /etc/shells"
chsh -s "$fish_shim"
```

The terminal can run fish without this; the step only changes SSH and TTY
logins.

## 9. Verify the machine

```sh
cd ~/repos/github.com/smores56/dotfiles
./install.sh                       # every path should report ok
tests/check.sh                     # source tree checks
mise ls                            # pinned tools are installed
flatpak list --user                # GUI applications are present
maki --version                     # pinned Maki release
sdlc list                          # pinned sdlc CLI reaches the registry
git config --show-origin user.email # resolves through machine.inc
worktrees list                     # runs inside a checkout
```
