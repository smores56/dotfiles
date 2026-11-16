# Interactive zsh. Environment for every zsh is in .zshenv; this file only
# loads zim and then conf.d/ in name order. Nothing here touches the network.

# zim's state and the completion dump live in the cache, not this directory.
ZIM_HOME=${XDG_CACHE_HOME:-$HOME/.cache}/zim
zstyle ':zim' disable-version-check yes
zstyle ':zim:completion' dumpfile "$ZIM_HOME/zcompdump"
# zsh-abbr's own file holds only abbreviations added on this machine; the
# shared ones are session abbreviations from conf.d.
ABBR_USER_ABBREVIATIONS_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/zsh-abbr/user-abbreviations

if [[ -r $ZIM_HOME/init.zsh ]]; then
  source "$ZIM_HOME/init.zsh"
else
  print -u2 'zsh: zim is not built; run `mise -C ~/repos/github.com/smores56/dotfiles bootstrap`'
fi

for _f in "$ZDOTDIR"/conf.d/*.zsh(N); do source "$_f"; done
unset _f
