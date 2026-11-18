# Operator steps

Everything here needs a human at the keyboard: a disk wipe, a root package
layer, a reboot, or a secret. Run the steps in order. Commands are exact; paths
are the ones this repository installs.

## 1. Before wiping the old disk

The FIDO2 credential handles live on the old machine. Back them up first; after
the wipe they are unrecoverable.

```sh
cd /srv/git/github.com/smores56/nix-config
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

## 2. Install Fedora atomic, then the smorespro image

Write an official Fedora atomic desktop ISO to a USB stick, boot it, and run
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

Do not add third-party repositories or layer packages during the install. The
image itself bakes in the one third-party repository this machine needs, Brave's
own RPM repository, for `brave-origin`; kitty, Dolphin, ImageMagick and jq come
from Fedora.

Then switch the host to the image this repository runs, following
[smorespro-image/docs/switch.md](https://github.com/smores56/smorespro-image/blob/main/docs/switch.md).
That switch is what brings niri, Noctalia, kitty, Dolphin, Brave Origin and the
other host packages; nothing is ever added with `rpm-ostree install`.

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

Clone the dotfiles repository at mise's default root:

```sh
git clone https://github.com/smores56/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

Install the latest mise and apply this machine's set. It asks for sudo once to
create `/srv/git` and hand it to you:

```sh
~/.dotfiles/scripts/install-mise.sh
```

It infers `desktop,identity` here (`DOTFILES_ENVS` overrides it) and runs
`mise bootstrap`; the [README](../README.md#bootstrap) covers what that applies.

## 4. Tailscale

Tailscale ships in the image and `tailscaled` is enabled, so there is no host
layer to add and no reboot:

```sh
sudo tailscale up
```

Authenticate in the browser window Tailscale opens. Confirm the node:

```sh
tailscale status
```

Enable HTTPS certificates for the tailnet in the admin console's DNS page:
step 10 serves the wallpaper tree over them. Tailscale SSH stays off; SSH to
smortress is the Cloudflare Access route in step 7a.

## 5. Maki and sdlc

```sh
cd ~/.dotfiles
scripts/install-maki.sh
maki --version
```

The Maki installer verifies the downloaded tarball against `maki/pin.env` and
the release's published `sha256sums.txt`. A mismatch aborts and installs
nothing. An update is a pin bump in `maki/pin.env` followed by a re-run; never
copy a release into `~/.local/bin` by hand.

`sdlc` is `sdlc/sdlc_issues.py` in this checkout, linked to `~/.local/bin/sdlc`
by the base environment. There is no private clone or install step: update
the source in the repository and re-apply the dotfiles. `sdlc list` calls `gh`,
so it starts working after step 6 authenticates the personal PAT.

## 6. Agent keys and personal token

The local agent's provider keys and the GitHub tokens live encrypted in
`sops.yaml`. The bootstrap task decrypts that file once into
`~/.config/secrets.env` (mode 600) when the admin age identity is present and
the ciphertext changed; the zsh `maki` launcher reads only that cache. The
machine's GitHub token goes to `~/.config/github-token` (mode 600), which
every zsh exports as `GH_TOKEN` for `gh`, git, and the `sdlc` CLI.

Verify without printing a key:

```sh
test -s ~/.config/secrets.env && echo keys-present
test "$(stat -c %a ~/.config/secrets.env)" = 600 && echo secrets-mode-ok
zsh -ic 'type -q maki && echo maki-launcher-ok'
test "$(stat -c %a ~/.config/github-token)" = 600 && echo token-mode-ok
gh auth status
sdlc list
```

The committed `sops.yaml` holds the encrypted values; edit it in place with
`sops`, using the passphrase-wrapped admin identity:

```sh
cd ~/.dotfiles
sops sops.yaml
```

Set `NEURALWATT_API_KEY` and `TINYFISH_API_KEY` from the named Bitwarden login
items. Set `GITHUB_PERSONAL_PAT` to a token with Contents read/write on your
repositories and Issues read/write on `smores56/sdlc`: without it, personal
machines have no git or `gh` access to GitHub. Set `GITHUB_WORK_PAT` to the
`smohr-blitzy` classic token with `repo` scope (lifetime at most 366 days,
which the Blitzy enterprise requires); only machines in the `work`
environment use it. The Cloudflare pair is step 6a. Save, commit the new
ciphertext, and run the bootstrap task again.

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
Never commit the plaintext values; `sops` re-encrypts on save.

## 6a. The Cloudflare Access service token

SSH to smortress goes through Cloudflare Access, so every client machine needs
one Access service token. Create it once in the Zero Trust dashboard under
**Access → Service Auth**, restricted to the SSH application (a token that
reaches the other applications is one leak away from the assistant's memory and
the backup reader), with a one-year lifetime; rotate it whenever a machine
leaves your control.

Put both halves in `sops.yaml` like any other cross-machine secret:

```sh
cd ~/.dotfiles
sops sops.yaml
```

- `CLOUDFLARE_ACCESS_CLIENT_ID` is the token's Client ID.
- `CLOUDFLARE_ACCESS_CLIENT_SECRET` is the token's Client Secret.

Save, commit the ciphertext, and re-run the delivery:

```sh
sh ~/.dotfiles/scripts/secrets.sh
```

The task writes `~/.config/cloudflare/access.env` (mode 600) and keeps the pair
out of `~/.config/secrets.env`, so nothing that reads the Maki cache holds it.
Only `~/.local/bin/smortress-ssh` reads the file, and only into cloudflared's
environment. Verify without printing the secret:

```sh
test -s ~/.config/cloudflare/access.env && echo access-token-present
test "$(stat -c %a ~/.config/cloudflare/access.env)" = 600 && echo access-mode-ok
grep -c . ~/.config/cloudflare/access.env   # 2 lines, no values printed
ssh smortress true && echo tunnel-ssh-with-token-ok
```

A machine without the file refuses the route and names it: there is no browser
login fallback, because the route is meant to work from a systemd unit or a GUI
launch, where no browser prompt can be answered.

## 6b. The YubiKey age recipient

`sops.yaml` is encrypted to the admin identity and, once enrolled, to the
YubiKey beside it, so `sops` decrypts with whichever identity is at hand and the
admin key stays as loss insurance. The recipient cannot be generated here: it
is derived from the token's hmac-secret, so this step needs the physical key.

The plugin installs as a mise tool (`github:olastor/age-plugin-fido2-hmac` in
`global/config.toml`, so `mise bootstrap` provides it). It links `libfido2`:
Fedora's image must ship `libfido2`, and the Mac needs `brew install libfido2`.

Generate the recipient and its handle with the token attached:

```sh
age-plugin-fido2-hmac -g | tee /tmp/yubikey-age.txt
```

It asks for the token's FIDO2 PIN, then for a touch, and prints a comment line
with the public key plus the `AGE-PLUGIN-FIDO2-HMAC-1...` identity. Answer
**yes** to "separate identity" so the recipient is a plain age key. Keep the
output as the identity file, readable only by you, and delete the copy:

```sh
install -d -m 700 ~/.config/sops
install -m 600 /tmp/yubikey-age.txt ~/.config/sops/fido2-identity.txt
shred -u /tmp/yubikey-age.txt
grep '^# public key:' ~/.config/sops/fido2-identity.txt   # the recipient
```

`~/.local/bin/sops-age-key` hands that file to `sops` whenever it exists, so no
passphrase is asked for; deleting the file is the documented fallback to the
admin identity.

Paste the printed `age1...` into `.sops.yaml`, uncommenting both lines:

```yaml
  # - &yubikey age1...
      - age:
          - *admin
          # - *yubikey
```

Then re-encrypt the data key to the new recipient and prove both identities
work:

```sh
cd ~/.dotfiles
sops updatekeys sops.yaml
sops -d sops.yaml >/dev/null && echo admin-identity-ok
mv ~/.config/sops/keys.age /tmp/keys.age.off
sops -d sops.yaml >/dev/null && echo yubikey-identity-ok   # touch the token
mv /tmp/keys.age.off ~/.config/sops/keys.age
```

Nothing else has to change: `sops.yaml` stays the only secret file, and the
private identity never enters this repository. The plugin is pre-1.0 upstream,
which is why the admin key stays enrolled. Clearing the token's FIDO2 PIN block
erases this credential along with the LUKS keyslot, the resident SSH handle and
the `pam_u2f` mapping; the admin key is then the recovery.

## 7. The work laptop's GitHub token

Restore the admin age identity (`~/.config/sops/keys.age`) before
smoreswork's first bootstrap; the bootstrap then writes `GITHUB_WORK_PAT` from
`sops.yaml` to `~/.config/github-token`.

## 7a. Reach smortress over its tunnel

smortress publishes SSH at `ssh.sammohr.dev` through its Cloudflare tunnel, and
Access is the only route for every machine, the work laptop included: no
Tailscale SSH, no VPN client. `~/.ssh/smortress.conf` carries the one route
(`ProxyCommand %d/.local/bin/smortress-ssh %h`), and both `~/.ssh/config` files
include it.

`cloudflared` comes from `brew:cloudflared` on smoreswork and from the pinned
`aqua:cloudflare/cloudflared` in `global/config.desktop.toml` on smorespro, so
`mise bootstrap` installs it either way. The wrapper reads the Access service
token from step 6a; without that file it stops and names it.

The key is the one smortress already accepts as `smores`: copy
`~/.ssh/id_smortress-access` (mode 600) from the password manager or the USB
backup. Both halves are needed: Access verifies the service token, sshd verifies
the key.

```sh
ssh smortress true && echo tunnel-ssh-ok
```

## 8. Login shell

Linux keeps bash as the login shell and uses the mise zsh for interactive
shells. No `/etc/shells` change and no `chsh` are needed:

```sh
readlink -f ~/.local/bin/zsh        # a binary under ~/.local/share/mise
zsh -ic 'echo $ZSH_VERSION'         # 5.9.x, with zimfw loaded
echo "$SHELL"                       # still bash
env | grep '^CONDA_' || true        # no CONDA_* variables leak
```

Open a new terminal and confirm the interactive shell is zsh. The login hook
skips any shell with a command string, so `bash -ilc 'echo $BASH_VERSION'`
must stay in bash. If the zsh link is missing, login falls back to bash.

## 9. Verify the machine

```sh
cd ~/.dotfiles
mise dot status                    # every dotfile target is applied
tests/check.sh                     # source tree checks
mise ls                            # pinned tools are installed
flatpak list --user                # GUI applications are present
maki --version                     # pinned Maki release
sdlc list                          # local sdlc CLI reaches the registry
git config --show-origin user.email # resolves through machine.inc
worktrees list                     # runs inside a checkout
```

## 10. Desktop specifics

The terminal, browser and file manager are system packages from the image:
`kitty`, `brave-origin` and `dolphin`. The image also supplies `ImageMagick`
and `jq` for wallpaper rotation. Confirm they start:

```sh
kitty --version
brave-origin --version             # Brave Origin is the only non-Fedora package
dolphin --version
```

Brave Origin has had upstream Fedora RPM launch bugs; if `Mod+B` does nothing,
run it from a terminal and check its stderr before relying on the bind.

Noctalia's GUI-managed state outranks `desktop/.config/noctalia/config.toml`,
so select the palette once even though the config file declares it:

```sh
noctalia msg color-scheme-set community "Rose Pine Moon"
```

Wallpaper rotation sets one image per display through Noctalia:

```sh
systemctl --user start wallpapers  # sync the cache and set every output
journalctl --user -u wallpapers -n 20
```

A run with no session (greetd, SSH) logs a skip instead of failing the unit.

The cache is mirrored over HTTPS from smortress, which serves `/srv/wallpapers`
with Tailscale's own file server: the request is authenticated by the device, so
the three-hourly timer carries no credential, and the old SFTP helper is gone.
On smortress, once:

```sh
sudo tailscale serve --bg --set-path /wallpapers /srv/wallpapers
tailscale serve status
```

`tailscale serve` needs HTTPS certificates enabled for the tailnet (admin
console, DNS page) and MagicDNS. `/srv/wallpapers` must hold the images; an
empty listing is reported and the cache kept. The URL is
`https://smortress.<tailnet>.ts.net/wallpapers/`, which the sync resolves from
`tailscale status --json` instead of a pinned tailnet name. Confirm the listing
before relying on the timer:

```sh
suffix=$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//; s/^[^.]*\.//')
curl -fsS "https://smortress.$suffix/wallpapers/" | head -n 5
```
