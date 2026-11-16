# PATH contract for the Fedora Atomic desktop.
#
# ~/.local/bin holds the installed `repos`, `worktrees`, `dev`, `wallpapers`,
# Maki, and mise; it comes first so a wrapper always wins over a system package
# of the same name. The mise shims follow, so a tool installed by `mise install`
# is found without activating mise in this file.
fish_add_path --prepend --global ~/.local/bin
fish_add_path --prepend --global ~/.local/share/mise/shims

set -gx EDITOR hx
set -gx VISUAL $EDITOR
set -gx PAGER less
set -gx LESS -FRX
set -gx BAT_THEME ansi
set -gx MANPAGER 'less -FRX'

# The employer's flat work checkout root, when it exists (see `repos` and the
# work includeIf in ~/.config/git/machine.inc).
if test -d ~/Blitzy
    set -gx BLITZY_REPOS_DIR ~/Blitzy
end

# sops unwraps the passphrase-protected admin age identity through this wrapper,
# so no plaintext identity is ever on disk. install.sh links the wrapper.
if test -x "$HOME/.local/bin/sops-age-key"
    set -gx SOPS_AGE_KEY_CMD "$HOME/.local/bin/sops-age-key"
end
