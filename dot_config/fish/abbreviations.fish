# workflow apps
abbr -a e "$EDITOR"
abbr -a l "exa --icons -lh"
abbr -a t "zellij-picker"
abbr -a f "lf"
abbr -a b "bat"
abbr -a g "lazygit"
abbr -a gc "git clone"

# searching
abbr -a / "fd --type f"
abbr -a // "sk --ansi -i -c 'rg --color=always --line-number \"{}\"'"

# theming
abbr -a dt "set-theme dark"
abbr -a lt "set-theme light"
abbr -a dts "set-theme dark --select"
abbr -a lts "set-theme light --select"

# dotfiles management
abbr -a cm "chezmoi"
abbr -a ccm "c ~/.local/share/chezmoi"
abbr -a cma "chezmoi apply"

# remote access
abbr -a s "ssh smores@home.sam-mohr.com -t"
abbr -a pf "port-forward smores@home.sam-mohr.com"
