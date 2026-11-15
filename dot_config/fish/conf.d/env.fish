# PATH contract, shared with ~/.zshrc on macOS.
#
# ~/.local/bin holds the `repos`, `worktrees`, and `dev` wrappers; it comes
# first so a wrapper always wins over a system package of the same name.
fish_add_path --prepend --global ~/.local/bin
fish_add_path --prepend --global ~/.local/share/mise/shims
fish_add_path --append --global ~/.cargo/bin

# Homebrew is the package source on macOS; keep its bin ahead of /usr/bin but
# behind ~/.local/bin. No `brew shellenv` call: it spawns a process on every
# shell start for values that never change.
if test -d /opt/homebrew/bin
    fish_add_path --append --global /opt/homebrew/bin /opt/homebrew/sbin
    set -gx HOMEBREW_NO_ANALYTICS 1
    set -gx HOMEBREW_NO_AUTO_UPDATE 1
end

set -gx EDITOR hx
set -gx VISUAL $EDITOR
set -gx PAGER less
set -gx LESS -FRX
set -gx BAT_THEME ansi
set -gx MANPAGER 'less -FRX'

# The employer's flat work checkout root, when it exists (see `repos` and the
# work includeIf in ~/.gitconfig).
if test -d ~/Blitzy
    set -gx BLITZY_REPOS_DIR ~/Blitzy
end

# sops unwraps the passphrase-protected admin age identity through this wrapper,
# so no plaintext identity is ever on disk. Installed by chezmoi at first apply.
if test -x "$HOME/.local/bin/sops-age-key"
    set -gx SOPS_AGE_KEY_CMD "$HOME/.local/bin/sops-age-key"
end
