# workflow apps
abbr -a e "$EDITOR"
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

# theming
abbr -a dt "set-theme dark"
abbr -a lt "set-theme light"
abbr -a dts "set-theme dark --select"
abbr -a lts "set-theme light --select"

# dotfiles management
abbr -a cdf "c ~/.dotfiles"
abbr -a dfi "~/.dotfiles/install"

# remote access
abbr -a s "ssh smores@home.sam-mohr.com -t"
abbr -a sp "ssh smores@pi.sam-mohr.com -t"
abbr -a pf "port-forward smores@home.sam-mohr.com"
