# What home-manager's zsh environment did, for every zsh (agents, launchd,
# editors run `zsh -c`): the Nix daemon profile, home-manager's session vars,
# then Homebrew appended so the employer's ~/.zshrc finds brew.
if [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  unset __ETC_PROFILE_NIX_SOURCED
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
if [[ -r $HOME/.nix-profile/etc/profile.d/hm-session-vars.sh ]]; then
  unset __HM_SESS_VARS_SOURCED
  . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
fi
[[ -d /opt/homebrew/bin ]] && path+=(/opt/homebrew/bin /opt/homebrew/sbin)
# Keep the dotfiles order on top of whatever those prepended.
path=("$HOME/.local/bin" "${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims" $path)
