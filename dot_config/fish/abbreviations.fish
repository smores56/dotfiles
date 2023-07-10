# workflow apps
abbr -a e "$EDITOR"
abbr -a ef "$EDITOR (gum file .)"
abbr -a l "exa --icons -lh"
abbr -a t "zellij-picker"
abbr -a a "mkdir -p"
abbr -a f "lf"
abbr -a b "bat"
abbr -a g "lazygit"
abbr -a gc "gh repo clone"

# searching
abbr -a / "fd --type f"
abbr -a // "sk --ansi -i -c 'rg --color=always --line-number \"{}\"'"

# package management
abbr -a pa "sudo apk add"
abbr -a pd "sudo apk del"

# theming
abbr -a dt "set-theme dark"
abbr -a lt "set-theme light"
abbr -a dts "set-theme dark --select"
abbr -a lts "set-theme light --select"

# dotfiles management
abbr -a cdf "c ~/.local/share/chezmoi"
abbr -a cm "chezmoi"
abbr -a ca "chezmoi apply"

# remote access
abbr -a sl "ssh smores@sammohr.dev -t"
abbr -a sm "ssh smores@home.sammohr.dev -t"
abbr -a sc "ssh smores@campfire.sammohr.dev -t"
abbr -a pf "port-forward smores@home.sammohr.dev"
