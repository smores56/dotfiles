# Operator steps

Steps that need a human: a disk wipe, a reboot, a secret, or a physical key.
Run them in order.

## 1. Before wiping the old disk

The FIDO2 credential handles live on the old machine and are unrecoverable
after the wipe. Back them up, copy the printed directory to external media, and
confirm it is there:

```sh
cd /srv/git/github.com/smores56/nix-config
nix run .#key-backup
ls -la <printed-directory>
```

Copy the hand-made SSH material and the sops age identity:

```sh
install -d /media/<usb>/ssh-backup /media/<usb>/sops-backup
cp -a ~/.ssh/. /media/<usb>/ssh-backup/
cp -a ~/.config/sops/. /media/<usb>/sops-backup/
ls -la /media/<usb>/ssh-backup/id_ed25519 /media/<usb>/sops-backup/keys.age
```

The provider API keys come from Bitwarden in step 6; nothing else is copied.

## 2. Install Fedora atomic, then the smorespro image

```sh
sudo dd if=<fedora-cosmic-atomic.iso> of=/dev/sdX bs=4M status=progress oflag=sync
```

In the installer, enable LUKS encryption for the root filesystem, create the
user `smores`, keep the default layout, and reboot. Add no repositories or
packages. Then switch to the image with
[smorespro-image/docs/switch.md](https://github.com/smores56/smorespro-image/blob/main/docs/switch.md);
it brings every host package.

## 3. First login: restore keys and bootstrap

```sh
install -d -m 700 ~/.ssh ~/.config/sops
cp -a /media/<usb>/ssh-backup/. ~/.ssh/
chmod 600 ~/.ssh/id_ed25519
install -m 600 /media/<usb>/sops-backup/keys.age ~/.config/sops/keys.age
curl -fsSL https://bootstrap.sammohr.dev | sh
```

## 3b. Migrating a machine still on a normal clone

Only a machine whose `~/.dotfiles` is a real directory needs this. Commit or
stash first. Clone from GitHub, not from `~/.dotfiles`, so `origin` does not
point at the directory about to be deleted:

```sh
repo=/srv/git/github.com/smores56/dotfiles
rm "$repo"                       # the old alias symlink; ~/.dotfiles stays intact
git clone --bare https://github.com/smores56/dotfiles.git "$repo/.git"
git -C "$repo" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
mv ~/.dotfiles ~/.dotfiles.old
git -C "$repo" worktree add "$repo/main" main
git -C "$repo/main" fetch origin
git -C "$repo/main" branch --set-upstream-to=origin/main
ln -s "$repo/main" ~/.dotfiles
```

Restore the ignored machine set, or the apply runs only the base environment.
Apply twice (the first apply after the move can prune links without recreating
them); the diff must end with `all files are applied` and `all edits are
applied`:

```sh
cp ~/.dotfiles.old/global/miserc.local.toml ~/.config/mise/miserc.local.toml
mise -C ~/.dotfiles install
mise -C ~/.dotfiles dot apply --prune
mise -C ~/.dotfiles dot apply --yes --prune
mise -C ~/.dotfiles dot diff
mise -C ~/.dotfiles ls --missing   # empty
git config alias.get               # no --global: that ignores includes
```

Then remove `~/.dotfiles.old`. `git get` refuses an existing path, so re-clone
other old normal clones:

```sh
rm -rf /srv/git/github.com/<owner>/<repo>
git get <owner>/<repo>
```

## 4. Tailscale

```sh
sudo tailscale up
tailscale status
```

Enable HTTPS certificates and MagicDNS in the admin console's DNS page; step 9
needs them. Tailscale SSH stays off.

## 5. Maki

```sh
~/.dotfiles/scripts/install-maki.sh
maki --version
```

## 6. Agent keys and GitHub tokens

Edit the ciphertext with the admin identity, then commit it and re-run the
bootstrap task:

```sh
cd ~/.dotfiles
sops sops.yaml
```

| Key | Value |
| --- | --- |
| `NEURALWATT_API_KEY`, `TINYFISH_API_KEY` | the named Bitwarden login items |
| `GITHUB_PERSONAL_PAT` | Contents read/write on your repositories, Issues read/write on `smores56/sdlc` |
| `GITHUB_WORK_PAT` | the `smohr-blitzy` classic token, `repo` scope, lifetime at most 366 days (Blitzy enterprise rule) |
| `CLOUDFLARE_ACCESS_*` | step 6a |

To read the Bitwarden values in a terminal:

```sh
bw() { flatpak run --command=bw com.bitwarden.desktop "$@"; }
bw login
BW_SESSION=$(bw unlock --raw) || { echo 'unlock failed' >&2; exit 1; }
export BW_SESSION
bw get password <neuralwatt-item>
bw get password <tinyfish-item>
unset BW_SESSION
```

Verify without printing a key:

```sh
test "$(stat -c %a ~/.config/maki/secrets.env)" = 600 && echo secrets-ok
test "$(stat -c %a ~/.config/gh/token)" = 600 && echo token-ok
head -1 "$(command -v maki)" | grep -q '^#!/bin/sh' && echo maki-wrapper-ok
gh auth status
sdlc list
```

## 6a. The Cloudflare Access service token

Create one service token in Zero Trust under **Access → Service Auth**,
restricted to the SSH application, with a one-year lifetime; rotate it whenever
a machine leaves your control. In `sops sops.yaml`, set
`CLOUDFLARE_ACCESS_CLIENT_ID` and `CLOUDFLARE_ACCESS_CLIENT_SECRET`, commit,
and deliver:

```sh
sh ~/.dotfiles/scripts/secrets.sh
test "$(stat -c %a ~/.config/cloudflare/access.env)" = 600 && echo access-ok
ssh smortress true && echo tunnel-ok
```

There is no browser-login fallback: the route must work from systemd units and
GUI launches.

## 6b. The YubiKey age recipient

The YubiKey recipient is enrolled in `.sops.yaml`. On a new machine, or after a
token reset (which erases the credential, the LUKS keyslot, the resident SSH
handle and the `pam_u2f` mapping), regenerate the handle with the token
attached. It needs `libfido2` (in the Fedora image; `brew install libfido2` on
the Mac). Answer **yes** to "separate identity":

```sh
age-plugin-fido2-hmac -g | tee /tmp/yubikey-age.txt
install -d -m 700 ~/.config/sops
install -m 600 /tmp/yubikey-age.txt ~/.config/sops/fido2-identity.txt
shred -u /tmp/yubikey-age.txt
grep '^# public key:' ~/.config/sops/fido2-identity.txt   # the recipient
```

After a reset, replace the `&yubikey` recipient in `.sops.yaml`, re-encrypt,
and prove each identity alone. `sops-age-key` uses the handle whenever it is
readable, so move it aside (inside `~/.config/sops`, never `/tmp`) to test the
admin key, and always move it back:

```sh
cd ~/.dotfiles
sops updatekeys sops.yaml
mv ~/.config/sops/fido2-identity.txt ~/.config/sops/fido2-identity.txt.off
sops -d sops.yaml >/dev/null && echo admin-identity-ok
mv ~/.config/sops/fido2-identity.txt.off ~/.config/sops/fido2-identity.txt
sops -d sops.yaml >/dev/null && echo yubikey-identity-ok   # PIN, then touch
```

The plugin is pre-1.0, so the admin key stays enrolled as recovery.

## 7. Reach smortress over its tunnel

SSH to smortress goes only through Cloudflare Access at `ssh.sammohr.dev`, on
every machine. Copy `~/.ssh/id_smortress-access` (mode 600) from the password
manager or the USB backup; Access checks the service token, sshd checks the key.
On smoreswork, restore `~/.config/sops/keys.age` before the first bootstrap so
it can write the work token.

```sh
ssh smortress true && echo tunnel-ssh-ok
```

## 8. Verify the machine

```sh
cd ~/.dotfiles
mise dot status
tests/check.sh
mise ls
flatpak list --user
git config --show-origin user.email   # resolves through machine.inc
```

Open a new kitty window: the prompt is pure (❯ on its own line) and `e`
expands to `hx`.

## 9. Desktop specifics

Select the palette once; Noctalia's GUI state outranks its config file:

```sh
noctalia msg color-scheme-set community "Rose Pine Moon"
```

If `Mod+B` does nothing, run `brave-origin` from a terminal and read its stderr.

Wallpapers sync over Tailscale's file server from smortress, authenticated by
the device. On smortress, once, with `/srv/wallpapers` holding the images:

```sh
sudo tailscale serve --bg --set-path /wallpapers /srv/wallpapers
tailscale serve status
```

On the desktop:

```sh
systemctl --user start wallpapers
journalctl --user -u wallpapers -n 20
```
