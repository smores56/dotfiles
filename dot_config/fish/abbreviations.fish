# workflow apps
abbr -a e "$EDITOR"
abbr -a ef "$EDITOR (gum file .)"
abbr -a l "exa --icons -lh"
abbr -a t zellij
abbr -a a "mkdir -p"
abbr -a f yazi
abbr -a b bat
abbr -a g lazygit
abbr -a gc "gh repo clone"

# searching
abbr -a / "fd --type f"
abbr -a // "sk --ansi -i -c 'rg --color=always --line-number \"{}\"'"

# Arch Linux
abbr -a pi "doas pacman -Sy"
abbr -a pr "doas pacman -R"
abbr -a pq "doas pacman -Q"

# theming
abbr -a dt "set-theme dark"
abbr -a lt "set-theme light"
abbr -a dts "set-theme dark --select"
abbr -a lts "set-theme light --select"

# dotfiles management
abbr -a cdf "c ~/.local/share/chezmoi"
abbr -a cm chezmoi
abbr -a ca "chezmoi apply"

# remote access
abbr -a sl "ssh smoresnet -t fish"
abbr -a sm "ssh smortress -t fish"
abbr -a sc "ssh campfire -t fish"
abbr -a st "ssh (tailscale-hosts | fzf) -t fish"
abbr -a pf "port-forward smores@home.sammohr.dev"
